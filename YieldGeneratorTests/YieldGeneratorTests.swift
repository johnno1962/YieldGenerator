//
//  YieldGeneratorTests.swift
//  YieldGeneratorTests
//
//  Created by John Holdsworth on 05/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//

import XCTest
import YieldGenerator

class YieldGeneratorTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func randomDelay() {
        NSThread.sleepForTimeInterval(Double(random()&0xff)*0.00001)
    }

    func testYieldGenerator() {
        // This is an example of a functional test case.

        for i in 0..<100 {
            var result = 0

            if ( true ) {
                let g = YieldGenerator<Int> {
                    (yield) in
                    for i in 0..<10 {
                        self.randomDelay()
                        yield(i)
                    }
                }

                while let v = g.next() {
                    randomDelay()
                    result=v
                }

                XCTAssertEqual(result,9,"result9")
            }

            for v in yieldSequence( {
                (yield : (Int) -> Bool) in
                for i in 0..<10 {
                    self.randomDelay()
                    if ( !yield(i) ) {
                        self.randomDelay()
                        break
                    }
                }
            } ) {
                randomDelay()
                result=v
                if ( v > 3 ) {
                    break
                }
            }

            XCTAssertEqual(result,4,"result4")
        }

        NSThread.sleepForTimeInterval(1.0)
        println(yeildGeneratorThreads)
        XCTAssertEqual(yeildGeneratorThreads,0,"threads cleared")
    }

    func testFileSequence() {
        var foundLine: String?
        for line in FILESequence(__FILE__) {
            println(line)
            // Logs to HERE
            if line.rangeOfString("// Logs to HERE") != nil {
                foundLine = line
                break
            }
        }
        XCTAssert(foundLine != nil && foundLine == "            // Logs to HERE","found line")
    }

    func textRegexSequence() {
        let groups = Array<[String?]>( regexSequence( "the quick brown fox", "(\\w{3})(\\w+)", nil ) )
        XCTAssertEqual(groups[0][0]!, "the")
        XCTAssertEqual(groups[0][0]!, "quick")
        XCTAssertEqual(groups[0][0]!, "brown")
        XCTAssertEqual(groups[0][0]!, "fox")
        XCTAssertNil(groups[0][1], "nil group")
        XCTAssertEqual(groups[1][1]!, "ck")
    }

    // original tests from https://github.com/kristopherjohnson/KJYield
    //
    // Copyright (c) 2014 Kristopher Johnson
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

    func testNumericSequence() {
        // Sequence [3, 6, 9, 12, 15]
        let seq: SequenceOf<Int> = yieldSequence { yield in
            for n in 0..<5 { yield((n+1) * 3) }
        }

        var a = Array<Int>(seq)
        XCTAssertEqual(5, a.count)
        XCTAssertEqual(3, a[0])
        XCTAssertEqual(6, a[1])
        XCTAssertEqual(9, a[2])
        XCTAssertEqual(12, a[3])
        XCTAssertEqual(15, a[4])
    }

    func testFibonacciSequence() {
        // Produce first 20 elements of Fibonacci sequence
        let fibs = Array<Int>(yieldSequence { yield in
            var a = 0, b = 1
            for _ in 0..<20 {
                yield(b)
                let sum = a + b
                a = b
                b = sum
            }
            })

        XCTAssertEqual(20, fibs.count)

        XCTAssertEqual(1,  fibs[0])
        XCTAssertEqual(1,  fibs[1])
        XCTAssertEqual(2,  fibs[2])
        XCTAssertEqual(3,  fibs[3])
        XCTAssertEqual(5,  fibs[4])
        XCTAssertEqual(8,  fibs[5])

        XCTAssertEqual(55, fibs[9])

        XCTAssertEqual(6765, fibs[19])
    }

    func testFizzBuzz() {
        let fizzBuzz = Array<String>(yieldSequence { yield in
            for n in 1...100 {
                if n % 3 == 0 {
                    if n % 5 == 0 {
                        yield("FizzBuzz")
                    }
                    else {
                        yield("Fizz")
                    }
                }
                else if n % 5 == 0 {
                    yield("Buzz")
                }
                else {
                    yield(n.description)
                }
            }
            })

        XCTAssertEqual(100, fizzBuzz.count)

        XCTAssertEqual("1",        fizzBuzz[0])
        XCTAssertEqual("2",        fizzBuzz[1])
        XCTAssertEqual("Fizz",     fizzBuzz[2])
        XCTAssertEqual("4",        fizzBuzz[3])
        XCTAssertEqual("Buzz",     fizzBuzz[4])
        XCTAssertEqual("Fizz",     fizzBuzz[5])
        XCTAssertEqual("7",        fizzBuzz[6])

        XCTAssertEqual("14",       fizzBuzz[13])
        XCTAssertEqual("FizzBuzz", fizzBuzz[14])
        XCTAssertEqual("16",       fizzBuzz[15])
    }

    func testLazySequence() {
        var yieldCount = 0
        var yielderComplete = false

        let seq: SequenceOf<Int> = yieldSequence { yield in
            ++yieldCount
            yield(1)

            ++yieldCount
            yield(2)

            ++yieldCount
            yield(3)

            yielderComplete = true
        }

        var gen = seq.generate()
        NSThread.sleepForTimeInterval(0.01)
        XCTAssertEqual(2, yieldCount, "yield should not be called until next()")
        XCTAssertFalse(yielderComplete)

        let val1 = gen.next()
        XCTAssertEqual(1, val1!)
        NSThread.sleepForTimeInterval(0.01)
        XCTAssertEqual(3, yieldCount, "should be blocked on second yield call")
        XCTAssertFalse(yielderComplete)

        let val2 = gen.next()
        XCTAssertEqual(2, val2!)
        NSThread.sleepForTimeInterval(0.01)
        XCTAssertEqual(3, yieldCount, "should be blocked on third yield call")
//        XCTAssertFalse(yielderComplete)

        let val3 = gen.next()
        XCTAssertEqual(3, val3!)
        XCTAssertTrue(yielderComplete, "should have run to completion")

        let val4 = gen.next()
        XCTAssertNil(val4, "should have no more values")
    }

    func testDeckOfCards() {
        let suits = ["Clubs", "Diamonds", "Hearts", "Spades"]
        let ranks = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace"]
        let seq: SequenceOf<String> = yieldSequence { yield in
            for suit in suits {
                for rank in ranks {
                    yield("\(rank) of \(suit)")
                }
            }
        }

        let deck = Array<String>(seq)
        XCTAssertEqual(52, deck.count)

        XCTAssertEqual("2 of Clubs",     deck[0])
        XCTAssertEqual("3 of Clubs",     deck[1])

        XCTAssertEqual("Ace of Clubs",   deck[12])
        XCTAssertEqual("2 of Diamonds",  deck[13])

        XCTAssertEqual("King of Spades", deck[50])
        XCTAssertEqual("Ace of Spades",  deck[51])
    }
    
    func testFibonacciPerformance() {
        // This is an example of a performance test case.
        self.measureBlock() {
            // Put the code you want to measure the time of here.
            for v in YieldGenerator<Double>({
                (yield) in
                var a=0.0, b=1.0
                for i in 0..<1000 {
                    yield(b)
                    let sum = a + b
                    a = b
                    b = sum
                }
                println(b)
            }).sequence() {
            }
        }
    }
    
}
