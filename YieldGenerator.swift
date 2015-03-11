//
//  YieldGenerator.swift
//  YieldGenerator - Python's "yield" for Swift generators
//
//  Created by John Holdsworth on 06/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
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

    private let thread: YieldThread<T>!

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
        dispatch_semaphore_signal(thread.wantsValue)
    }
}

private let yieldQueue = dispatch_queue_create("YieldThreads", DISPATCH_QUEUE_CONCURRENT)
public var yeildGeneratorThreads = 0

private final class YieldThread<T> {

    private let valueAvailable = dispatch_semaphore_create(0)
    private let wantsValue = dispatch_semaphore_create(0)

    private weak var owner: YieldGenerator<T>?
    private var lastValue: T?

    init( _ generator: YieldGenerator<T>, _ yielder: ((T) -> Bool) -> () ) {
        owner = generator
        yeildGeneratorThreads++
        dispatch_semaphore_signal(wantsValue)
        dispatch_async(yieldQueue, {
            yielder(self.yeilded)
            if self.owner != nil {
                dispatch_semaphore_wait(self.wantsValue, DISPATCH_TIME_FOREVER)
                self.lastValue = nil
                dispatch_semaphore_signal(self.valueAvailable)
            }
            yeildGeneratorThreads--
        })
    }

    func yeilded(value:T) -> Bool {
        if owner != nil {
            dispatch_semaphore_wait(wantsValue, DISPATCH_TIME_FOREVER)
            lastValue = value
            dispatch_semaphore_signal(valueAvailable)
            return true
        } else {
            return false
        }
    }

    func next() -> T? {
        dispatch_semaphore_wait(valueAvailable, DISPATCH_TIME_FOREVER)
        let value = lastValue
        dispatch_semaphore_signal(wantsValue)
        return value
    }
}

public func yieldSequence<T> ( yielder: ((T) -> Bool) -> () ) -> SequenceOf<T> {
    return YieldGenerator( yielder ).sequence()
}

public func regexSequence( input: NSString, pattern: NSString, _ options: NSRegularExpressionOptions = .CaseInsensitive ) -> SequenceOf<[String?]> {
    return yieldSequence {
        (yield) in
        var error: NSError?
        if let regex = NSRegularExpression( pattern: pattern, options: options, error: &error ) {
            regex.enumerateMatchesInString( input, options: nil, range: NSMakeRange(0,input.length), usingBlock: {
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
            println("YieldGenerator: regexSequence error:\(error?.localizedDescription)")
        }
    }
}

public func FILESequence( filepath: NSString ) -> SequenceOf<NSString> {
    return yieldSequence {
        (yield) in
        let fp = filepath.substringFromIndex(filepath.length-1) == "|" ?
            popen( filepath.substringToIndex(filepath.length-1), "r" ) :
            fopen( filepath.UTF8String, "r" )
        if fp != nil {
            var buffer = [Int8](count: 10000, repeatedValue: 0)

            while fgets( UnsafeMutablePointer<Int8>(buffer), Int32(buffer.count), fp ) != nil {
                let newlinePos = strlen(buffer)-1 as Int
                if newlinePos >= 0 {
                    buffer[newlinePos] = 0
                }
                if !yield( NSString( UTF8String: buffer )! ) {
                    break
                }
            }

            pclose( fp )
        } else {
            println( "YieldGenerator: FILESequence could not open: \(filepath), \(strerror(errno))" )
        }
    }
}

#if os(OSX)

public var yieldTaskExitStatus: Int32!

public func TaskSequence( task: NSTask, linesep: NSString = "\n",
    filter: NSString? = nil ) -> SequenceOf<NSString> {

    task.standardOutput = NSPipe()
    let stdout = task.standardOutput.fileHandleForReading

    task.standardError = NSPipe()
    task.standardError.fileHandleForReading.readabilityHandler = {
        (fhandle) in
        println("YieldGenerator: TaskSequence stderr: "+fhandle.availableData.string)
    }

    task.launch()

    let buffer = NSMutableData( data: stdout.availableData )

    return yieldSequence {
        (yield) in
        let eolChar = linesep.characterAtIndex(0)
        let NULL = UnsafePointer<Void>.null()
        let filterBytes = filter?.UTF8String

        var endOfInput = false, terminated = false
        while !(endOfInput && buffer.length == 0) && !terminated {

            while buffer.length != 0 {
                let endOfLine = memchr( buffer.bytes, Int32(eolChar), UInt(buffer.length) )
                if endOfLine == NULL && !endOfInput {
                    break
                }

                let bytes = UnsafeMutablePointer<Int8>(buffer.bytes)
                let length = endOfLine != NULL ? endOfLine-buffer.bytes : buffer.length

                if filter == nil || strnstr( bytes, filterBytes!, UInt(length) ) != NULL {
                    if !yield( NSData( bytesNoCopy: bytes, length: length, freeWhenDone: false ).string ) {
                        terminated = true
                        task.terminate()
                        break
                    }
                }

                buffer.replaceBytesInRange( NSMakeRange(0,min(length+1,buffer.length)), withBytes:nil, length:0 )
            }

            if !endOfInput && !terminated {
                var data = stdout.availableData
                if data.length != 0 {
                    buffer.appendData( data )
                } else {
                    endOfInput = true
                }
            }
        }

        task.waitUntilExit()
        yieldTaskExitStatus = task.terminationStatus
    }
}

public func CommandSequence( command: String, workingDirectory: String = "/tmp",
    linesep: NSString = "\n", filter: String? = nil ) -> SequenceOf<NSString> {
        let task = NSTask()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.currentDirectoryPath = workingDirectory
        return TaskSequence( task, linesep: linesep, filter: filter )
}
#endif

extension NSData {
    var string: NSString {
        if let string = NSString( data: self, encoding: NSUTF8StringEncoding ) {
            return string
        } else {
            println( "YieldGenerator: Falling back to NSISOLatin1StringEncoding" )
            return NSString( data: self, encoding: NSISOLatin1StringEncoding )!
        }
    }
}

