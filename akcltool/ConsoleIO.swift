//
//  ConsoleIO.swift
//  AugmentKitCLTools
//
//  Created by Jamie Scanlon on 12/2/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation

enum ConsoleOutputType {
    case error
    case standard
}

class ConsoleIO {
    
    static func writeMessage(_ message: String, to: ConsoleOutputType = .standard) {
        switch to {
        case .standard:
            print("\u{001B}[;m\(message)")
        case .error:
            fputs("\u{001B}[0;31m\(message)\n", stderr)
        }
    }
    
    static func printUsage() {
        
        let executableName = (CommandLine.arguments[0] as NSString).lastPathComponent
        
        writeMessage("usage:")
        writeMessage("\(executableName) -s [path] : Serialize a model file at a given path and save the serialized file to the same directory")
        writeMessage("or")
        writeMessage("\(executableName) -h to show usage information")
    }
    
}
