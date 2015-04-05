## YieldGenerator - Python's "yield" generators for Swift

The YieldGenerator class and the associated yieldSequence allow you recode generators as closure containing a loop using a thread and semaphores internally to implement "inversion of control". For example, a loop to implement the first 20 numbers in the Fibanacci series can be expressed as follows:

```Swift
    let generator = YieldGenerator<Int> {
        (yield : (Int) -> Bool) in
        var a = 0, b = 1
        for _ in 0..<20 {
            if !yield(b) {
                break
            }
            let sum = a + b
            a = b
            b = sum
        }
    }

    while let value = generator.next() {
        println("Value: \(value)")
    }
```

A generator can be used in a for loop by converting it into a sequence:

```Swift
    for value in generator.sequence() {
        println("Value: \(value)")
    }
```

Or you can wrap the generator up by using the yieldSequence() function

```Swift
    for value in yieldSequence( {
        (yield : (Int) -> Bool) in
        var a = 0, b = 1
        for _ in 0..<20 {
            if !yield(b) {
                break
            }
            let sum = a + b
            a = b
            b = sum
        }
    } ) {
        println("Value: \(value)")
    }
```

The generator loop is run in it's own thread calling yield() when it wants to make a value available to the generator. The boolean value returned by the yield closure is false if the loop consuming the generator's sequence has exited and the yield loop itself should exit.

I'd thought this was an original idea but the terrain was already surveyed by [Kristopher Johnson](https://gist.github.com/kristopherjohnson/68711422475ecc010e05) just a month after Swift came out! Anyway, this is my take on it. I've included Kristopher's tests for sanity.

On OSX the following api also is available that can be used to the output to process output of a UNIX command, something like popen() of old..

```Swift
    public func CommandSequence( command: String, workingDirectory: String = "/tmp",
        linesep: NSString = "\n", filter: String? = nil, filter2: String? = nil ) -> SequenceOf<NSString>
```

Finally, as NSTask() and fork()'s in general for Cocoa processes are quite expensive I've added the much faster:

```Swift
    public func BashSequence( command: String, workingDirectory: String = "/tmp" ) -> SequenceOf<NSString>
```

This runs up a single bash process for all subcommands which are written to standard input rather than forking each time. Ouput is delimited by a token \_\_\_END\_\_\_ $status so output of the subprocess must finish with a newline.

### License MIT

Copyright (c) 2015 John Holdsworth

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

