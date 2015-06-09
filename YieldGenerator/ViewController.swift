//
//  ViewController.swift
//  YieldGenerator
//
//  Created by John Holdsworth on 05/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

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

//        for value in generator.sequence() {
//            println("Value: \(value)")
//        }
//
        while let value = generator.next() {
            print("Value: \(value)")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

