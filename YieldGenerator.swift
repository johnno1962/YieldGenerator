//
//  YieldGenerator.swift
//  YieldGenerator - Python's "yield" for Swift generators
//
//  Created by John Holdsworth on 06/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/YieldGenerator/YieldGenerator.swift#9 $
//
//  Repo: https://github.com/johnno1962/YieldGenerator
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation

public class YieldGenerator<T>: GeneratorType {

    private var thread: YieldThread<T>!

    public init( _ yielder: ((T) -> Bool) -> () ) {
        thread = YieldThread<T>( self, yielder )
    }

    public func next() -> T? {
        return thread.next()
    }

    public func sequence() -> SequenceOf<T> {
        return SequenceOf({self})
    }

    deinit {
        dispatch_semaphore_signal( thread.wantsValue )
    }
}

private let yieldQueue = dispatch_queue_create( "YieldThreads", DISPATCH_QUEUE_CONCURRENT )
public var yeildGeneratorThreads = 0

private final class YieldThread<T> {

    private let valueAvailable = dispatch_semaphore_create(0)
    private let wantsValue = dispatch_semaphore_create(0)

    private weak var owner: YieldGenerator<T>?
    private var lastValue: T?

    init( _ generator: YieldGenerator<T>, _ yielder: ((T) -> Bool) -> () ) {
        owner = generator
        yeildGeneratorThreads++
        dispatch_semaphore_signal( wantsValue )
        dispatch_async( yieldQueue, {
            yielder( self.yeilded )
            if self.owner != nil {
                dispatch_semaphore_wait( self.wantsValue, DISPATCH_TIME_FOREVER )
                self.lastValue = nil
                dispatch_semaphore_signal( self.valueAvailable )
            }
            yeildGeneratorThreads--
        })
    }

    func yeilded( value:T ) -> Bool {
        if owner != nil {
            dispatch_semaphore_wait( wantsValue, DISPATCH_TIME_FOREVER )
            lastValue = value
            dispatch_semaphore_signal( valueAvailable )
            return true
        } else {
            return false
        }
    }

    func next() -> T? {
        dispatch_semaphore_wait( valueAvailable, DISPATCH_TIME_FOREVER )
        let value = lastValue
        dispatch_semaphore_signal( wantsValue )
        return value
    }
}

public func yieldSequence<T> ( yielder: ((T) -> Bool) -> () ) -> SequenceOf<T> {
    return YieldGenerator( yielder ).sequence()
}

public func regexSequence( input: NSString, pattern: String, _ options: NSRegularExpressionOptions = .CaseInsensitive ) -> SequenceOf<[String?]> {
    return yieldSequence {
        (yield) in
        var error: NSError?
        if let regex = NSRegularExpression( pattern: pattern, options: options, error: &error ) {
            regex.enumerateMatchesInString( input as String, options: nil, range: NSMakeRange(0,input.length), usingBlock: {
                (match, flags, shouldStop) in
                var groups = [String?]()
                for groupno in 0...regex.numberOfCaptureGroups {
                    let range = match.rangeAtIndex(groupno)
                    if ( range.location != NSNotFound ) {
                        groups.append( input.substringWithRange(range) )
                    } else {
                        groups.append( nil )
                    }
                }
                if !yield( groups ) {
                    shouldStop.memory = true
                }
            } )
        } else {
            println( "YieldGenerator: regexSequence error:\(error?.localizedDescription)" )
        }
    }
}

public var yieldTaskExitStatus: Int32!

public func FILESequence( filepath: NSString ) -> SequenceOf<String> {
    return yieldSequence {
        (yield) in
        let fp = filepath.substringFromIndex(filepath.length-1) == "|" ?
            popen( filepath.substringToIndex(filepath.length-1), "r" ) :
            fopen( filepath.UTF8String, "r" )
        if fp != nil {
            var buffer = [Int8](count: 10000, repeatedValue: 0)

            while fgets( UnsafeMutablePointer<Int8>(buffer), Int32(buffer.count), fp ) != nil {
                let newlinePos = Int(strlen(buffer)-1)
                if newlinePos >= 0 {
                    buffer[newlinePos] = 0
                }
                if !yield( String( UTF8String: buffer )! ) {
                    break
                }
            }

            yieldTaskExitStatus = pclose( fp ) >> 8
        } else {
            println( "YieldGenerator: FILESequence could not open: \(filepath), \(NSString( UTF8String: strerror(errno) )!)" )
        }
    }
}

public class CommandGenerator: GeneratorType {

    let fp: UnsafeMutablePointer<FILE>
    var buffer = [Int8](count: 10001, repeatedValue: 0)

    public init( _ command: String ) {
        fp = popen( command, "r" )
    }

    public func next() -> String? {
        if fgets( UnsafeMutablePointer<Int8>(buffer), Int32(buffer.count-1), fp ) != nil {
            let newlinePos = Int(strlen(buffer)-1)
            if newlinePos >= 0 {
                buffer[newlinePos] = 0
            }
            return String( UTF8String: buffer )!
        } else {
            return nil
        }
    }

    public func sequence() -> SequenceOf<String> {
        return SequenceOf({self})
    }

    deinit {
        yieldTaskExitStatus = pclose( fp ) >> 8
    }
}

#if os(OSX)

public func TaskSequence( task: NSTask, linesep: NSString = "\n",
    filter: NSString? = nil, filter2: NSString? = nil ) -> SequenceOf<String> {

    task.standardOutput = NSPipe()
    let stdout = task.standardOutput.fileHandleForReading

    task.standardError = NSPipe()
    task.standardError.fileHandleForReading.readabilityHandler = {
        (fhandle) in
        println("YieldGenerator: TaskSequence stderr: "+fhandle.availableData.string)
    }

    task.launch()

    return yieldSequence {
        (yield) in
        let eolChar = linesep.characterAtIndex(0)
        let filterBytes = filter?.UTF8String
        let filter2Bytes = filter2?.UTF8String
        let filter2Length = filter2 != nil ? strlen( filter2Bytes! ) : 0;

        let buffer = NSMutableData()

        var endOfInput = false
        do {

            if !endOfInput {
                var data = stdout.availableData
                if data.length != 0 {
                    buffer.appendData( data )
                } else {
                    endOfInput = true
                }
            }

            while buffer.length != 0 {
                let endOfLine = memchr( buffer.bytes, Int32(eolChar), Int(buffer.length) )
                if endOfLine == nil && !endOfInput {
                    break
                }

                let bytes = UnsafeMutablePointer<Int8>(buffer.bytes)
                let length = endOfLine != nil ? endOfLine-buffer.bytes : buffer.length

                if filter == nil && filter2 == nil ||
                        filter != nil && strnstr( bytes, filterBytes!, Int(length) ) != nil ||
                        filter2 != nil && strncmp( bytes, filter2Bytes!, Int(filter2Length) ) == 0 {
                    if !yield( NSData( bytesNoCopy: bytes, length: length, freeWhenDone: false ).string ) {
                        task.terminate()
                        task.standardInput.fileHandleForWriting?.closeFile()
                        task.standardOutput.fileHandleForReading.closeFile()
                        task.standardError.fileHandleForReading.closeFile()
                        yieldTaskExitStatus = -1
                        return
                    }
                }

                buffer.replaceBytesInRange( NSMakeRange(0,min(length+1,buffer.length)), withBytes:nil, length:0 )
            }

        } while !(endOfInput && buffer.length == 0)

        task.waitUntilExit()
        yieldTaskExitStatus = task.terminationStatus
    }
}

public func CommandSequence( command: String, workingDirectory: String = "/tmp",
    linesep: NSString = "\n", filter: String? = nil, filter2: String? = nil ) -> SequenceOf<String> {
        let task = NSTask()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command+" 2>&1"]
        task.currentDirectoryPath = workingDirectory
        return TaskSequence( task, linesep: linesep, filter: filter, filter2: filter2 )
}

private var bashGenerator: GeneratorOf<String>?
private var bashStandardInput: NSFileHandle!
private var bashLock = NSLock()

public func BashSequence( command: String, workingDirectory: String = "/tmp" ) -> SequenceOf<String> {
    bashLock.lock()
    if bashGenerator == nil {
        let task = NSTask()
        task.launchPath = "/bin/bash"
        task.currentDirectoryPath = "/tmp"
        task.standardInput = NSPipe()
        bashStandardInput = task.standardInput.fileHandleForWriting
        bashGenerator = TaskSequence( task ).generate()
    }
    return SequenceOf({BashGenerator( command, workingDirectory: workingDirectory )})
}

private var bashEOF = "___END___ " as NSString

private class BashGenerator: GeneratorType {

    init( _ command: String, workingDirectory: String = "/tmp" ) {
        let command = "(cd \"\(workingDirectory)\" && \(command) 2>&1)"
        let utf8 = (command+" ; echo \"\(bashEOF)$?\"\n" as NSString).UTF8String
        bashStandardInput.writeData( NSData( bytesNoCopy:
            UnsafeMutablePointer<Void>( utf8 ),
            length: Int(strlen( utf8 )), freeWhenDone: false ) )
    }

    func next() -> String? {
        if let next = bashGenerator?.next() {
            if !next.hasPrefix(bashEOF as String) {
                return next
            }
            else {
                let status = (next as NSString).substringFromIndex( bashEOF.length )
                yieldTaskExitStatus = Int32(status.toInt()!)
            }
        } else {
            NSLog( "BashGenerator Exited!" )
            bashGenerator = nil
        }
        bashLock.unlock()
        return nil
    }
}

#endif

extension NSData {
    var string: String {
        if let string = NSString( data: self, encoding: NSUTF8StringEncoding ) {
            return string as String
        } else {
            println( "YieldGenerator: Falling back to NSISOLatin1StringEncoding" )
            return NSString( data: self, encoding: NSISOLatin1StringEncoding )! as String
        }
    }
}

