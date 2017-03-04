//
//  YieldGenerator.swift
//  YieldGenerator - Python's "yield" for Swift generators
//
//  Created by John Holdsworth on 06/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/YieldGenerator/YieldGenerator.swift#13 $
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

open class YieldGenerator<T>: IteratorProtocol {

    fileprivate var thread: YieldThread<T>!

    public init( _ yielder: @escaping ((T) -> Bool) -> () ) {
        thread = YieldThread<T>( self, yielder )
    }

    open func next() -> T? {
        return thread.next()
    }

    open func sequence() -> AnySequence<T> {
        return AnySequence({self})
    }

    deinit {
        thread.wantsValue.signal()
    }
}

private let yieldQueue = DispatchQueue( label: "YieldThreads", attributes: DispatchQueue.Attributes.concurrent )
public var yeildGeneratorThreads = 0

private final class YieldThread<T> {

    fileprivate let valueAvailable = DispatchSemaphore(value: 0)
    fileprivate let wantsValue = DispatchSemaphore(value: 0)

    fileprivate weak var owner: YieldGenerator<T>?
    fileprivate var lastValue: T?

    init( _ generator: YieldGenerator<T>, _ yielder: @escaping ((T) -> Bool) -> () ) {
        owner = generator
        yeildGeneratorThreads += 1
        wantsValue.signal()
        yieldQueue.async(execute: {
            yielder( self.yeilded )
            if self.owner != nil {
                self.wantsValue.wait(timeout: DispatchTime.distantFuture )
                self.lastValue = nil
                self.valueAvailable.signal()
            }
            yeildGeneratorThreads -= 1
        })
    }

    func yeilded( _ value:T ) -> Bool {
        if owner != nil {
            wantsValue.wait(timeout: DispatchTime.distantFuture )
            lastValue = value
            valueAvailable.signal()
            return true
        } else {
            return false
        }
    }

    func next() -> T? {
        valueAvailable.wait(timeout: DispatchTime.distantFuture )
        let value = lastValue
        wantsValue.signal()
        return value
    }
}

public func yieldSequence<T> ( _ yielder: @escaping ((T) -> Bool) -> () ) -> AnySequence<T> {
    return YieldGenerator( yielder ).sequence()
}

public func regexSequence( _ input: NSString, pattern: String, _ options: NSRegularExpression.Options! = .caseInsensitive ) -> AnySequence<[String?]> {
    return yieldSequence {
        (yield) in
        var error: NSError?
        if let regex = try? NSRegularExpression( pattern: pattern, options: options ) {
            regex.enumerateMatches( in: input as String, options: [], range: NSMakeRange(0,input.length), using: {
                (match, flags, shouldStop) in
                var groups = [String?]()
                for groupno in 0...regex.numberOfCaptureGroups {
                    let range = match!.rangeAt(groupno)
                    if ( range.location != NSNotFound ) {
                        groups.append( input.substring(with: range) )
                    } else {
                        groups.append( nil )
                    }
                }
                if !yield( groups ) {
                    shouldStop.pointee = true
                }
            } )
        } else {
            print( "YieldGenerator: regexSequence error:\(error?.localizedDescription)" )
        }
    }
}

@_silgen_name("popen")
func _popen( _ command: UnsafePointer<Int8>, _ perms: UnsafePointer<Int8> ) -> UnsafeMutablePointer<FILE>

@_silgen_name("pclose")
func _pclose( _ fp: UnsafeMutablePointer<FILE> ) -> Int32

public var yieldTaskExitStatus: Int32!

public func FILESequence( _ filepath: NSString ) -> AnySequence<String> {
    return yieldSequence {
        (yield) in
        if let fp = filepath.substring(from: filepath.length-1) == "|" ?
            _popen( filepath.substring(to: filepath.length-1), "r" ) :
            fopen( filepath.utf8String, "r" ) {
            var buffer = [Int8](repeating: 0, count: 10000)

            while fgets( UnsafeMutablePointer<Int8>(mutating: buffer), Int32(buffer.count), fp ) != nil {
                let newlinePos = Int(strlen(buffer))-1
                if newlinePos >= 0 {
                    buffer[newlinePos] = 0
                }
                if !yield( String( validatingUTF8: buffer )! ) {
                    break
                }
            }

            yieldTaskExitStatus = _pclose( fp ) >> 8
        } else {
            print( "YieldGenerator: FILESequence could not open: \(filepath), \(NSString( utf8String: strerror(errno) )!)" )
        }
    }
}

open class CommandGenerator: IteratorProtocol {

    let fp: UnsafeMutablePointer<FILE>
    var buffer = [Int8](repeating: 0, count: 10001)

    public init( _ command: String ) {
        fp = _popen( command, "r" )
    }

    open func next() -> String? {
        if fgets( UnsafeMutablePointer<Int8>(mutating: buffer), Int32(buffer.count-1), fp ) != nil {
            let newlinePos = Int(strlen(buffer))-1
            if newlinePos >= 0 {
                buffer[newlinePos] = 0
            }
            return String( validatingUTF8: buffer )!
        } else {
            return nil
        }
    }

    open func sequence() -> AnySequence<String> {
        return AnySequence({self})
    }

    deinit {
        yieldTaskExitStatus = _pclose( fp ) >> 8
    }
}

#if os(OSX)

public func TaskSequence( task: NSTask, linesep: NSString = "\n",
    filter: NSString? = nil, filter2: NSString? = nil ) -> AnySequence<String> {

    task.standardOutput = NSPipe()
    let stdout = task.standardOutput!.fileHandleForReading

    task.standardError = NSPipe()
    task.standardError!.fileHandleForReading.readabilityHandler = {
        (fhandle) in
        print("YieldGenerator: TaskSequence stderr: "+fhandle.availableData.string)
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
        repeat {

            if !endOfInput {
                let data = stdout.availableData
                if data.length != 0 {
                    buffer.appendData( data )
                } else {
                    endOfInput = true
                }
            }

            while buffer.length != 0 {
                let endOfLine = UnsafeMutablePointer<Int8>( memchr( buffer.bytes, Int32(eolChar), Int(buffer.length) ) )
                if endOfLine == nil && !endOfInput {
                    break
                }

                let bytes = UnsafeMutablePointer<Int8>(buffer.bytes)
                let length = endOfLine != nil ? endOfLine-bytes : buffer.length

                if filter == nil && filter2 == nil ||
                        filter != nil && strnstr( bytes, filterBytes!, Int(length) ) != nil ||
                        filter2 != nil && strncmp( bytes, filter2Bytes!, Int(filter2Length) ) == 0 {
                    if !yield( NSData( bytesNoCopy: bytes, length: length, freeWhenDone: false ).string ) {
                        task.terminate()
                        task.standardInput!.fileHandleForWriting?.closeFile()
                        task.standardOutput!.fileHandleForReading.closeFile()
                        task.standardError!.fileHandleForReading.closeFile()
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
    linesep: NSString = "\n", filter: String? = nil, filter2: String? = nil ) -> AnySequence<String> {
        let task = NSTask()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command+" 2>&1"]
        task.currentDirectoryPath = workingDirectory
        return TaskSequence( task, linesep: linesep, filter: filter, filter2: filter2 )
}

private var bashGenerator: AnyGenerator<String>?
private var bashStandardInput: NSFileHandle!
private var bashLock = NSLock()

public func BashSequence( command: String, workingDirectory: String = "/tmp" ) -> AnySequence<String> {
    bashLock.lock()
    if bashGenerator == nil {
        let task = NSTask()
        task.launchPath = "/bin/bash"
        task.currentDirectoryPath = "/tmp"
        task.standardInput = NSPipe()
        bashStandardInput = task.standardInput!.fileHandleForWriting
        bashGenerator = TaskSequence( task ).generate()
    }
    return AnySequence({BashGenerator( command, workingDirectory: workingDirectory )})
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
                yieldTaskExitStatus = Int32(Int(status)!)
            }
        } else {
            NSLog( "YieldGenerator: BashGenerator Exited!" )
            bashGenerator = nil
        }
        bashLock.unlock()
        return nil
    }
}

#endif

extension Data {
    var string: String {
        if let string = NSString( data: self, encoding: String.Encoding.utf8.rawValue ) {
            return string as String
        } else {
            print( "YieldGenerator: Falling back to NSISOLatin1StringEncoding" )
            return NSString( data: self, encoding: String.Encoding.isoLatin1.rawValue )! as String
        }
    }
}
