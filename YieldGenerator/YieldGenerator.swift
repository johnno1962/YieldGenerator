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
        yeildGeneratorThreads++
        owner = generator
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
        }
        else {
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

public func FILESequence( filepath: NSString ) -> SequenceOf<NSString> {
    return yieldSequence {
        (yield) in
        let fp = filepath.substringFromIndex(filepath.length-1) == "|" ?
            popen( filepath.substringToIndex(filepath.length-1), "r" ) :
            fopen( filepath.UTF8String, "r" )
        if fp != nil {
            let buffer = [Int8](count: 10000, repeatedValue: 0)

            while fgets( UnsafeMutablePointer<Int8>(buffer), Int32(buffer.count), fp ) != nil {
                if !yield( NSString( UTF8String: buffer )! ) {
                    break
                }
            }

            pclose( fp )
        }
    }
}

public func regexSequence( input: NSString, pattern: NSString, options: NSRegularExpressionOptions ) -> SequenceOf<[String?]> {
    return yieldSequence {
        (yield) in
        var error: NSError?
        if let regex = NSRegularExpression(pattern: pattern, options: options, error: &error) {
            regex.enumerateMatchesInString(input, options: nil, range: NSMakeRange(0,input.length), usingBlock: {
                (match, flags, shouldStop) in
                var groups = [String?]()
                for groupno in 0...regex.numberOfCaptureGroups {
                    let range = match.rangeAtIndex(groupno)
                    if ( range.location != NSNotFound ) {
                        groups.append( input.substringWithRange(range) )
                    }
                    else {
                        groups.append( nil )
                    }
                }
                if !yield( groups ) {
                    shouldStop.memory = true
                }
            })
        } else {
            println("regexSequence error:\(error?.localizedDescription)" )
            return
        }
    }
}


