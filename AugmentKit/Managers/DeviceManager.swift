//
//  DeviceManager.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2018 JamieScanlon
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import UIKit

public class DeviceManager {
    
    public static var shared = DeviceManager()
    
    public enum ScreenHeights: Int {
        case inches_3_5
        case inches_4
        case inches_4_7
        case inches_5_5
    }
    
    public func isSize(_ height: ScreenHeights) -> Bool {
        let deviceHeight = deviceRect().height
        var targetHight: CGFloat = 0
        switch height {
        case .inches_3_5:
            targetHight = Heights.inches_3_5.rawValue
        case .inches_4:
            targetHight = Heights.inches_4.rawValue
        case .inches_4_7:
            targetHight = Heights.inches_4_7.rawValue
        case .inches_5_5:
            targetHight = Heights.inches_5_5.rawValue
        }
        return deviceHeight == targetHight
    }
    
    public func isSizeOrLarger(_ height: ScreenHeights) -> Bool {
        let deviceHeight = deviceRect().height
        var targetHight: CGFloat = 0
        switch height {
        case .inches_3_5:
            targetHight = Heights.inches_3_5.rawValue
        case .inches_4:
            targetHight = Heights.inches_4.rawValue
        case .inches_4_7:
            targetHight = Heights.inches_4_7.rawValue
        case .inches_5_5:
            targetHight = Heights.inches_5_5.rawValue
        }
        return deviceHeight >= targetHight
    }
    
    public func isSizeOrSmaller(_ height: ScreenHeights) -> Bool {
        let deviceHeight = deviceRect().height
        var targetHight: CGFloat = 0
        switch height {
        case .inches_3_5:
            targetHight = Heights.inches_3_5.rawValue
        case .inches_4:
            targetHight = Heights.inches_4.rawValue
        case .inches_4_7:
            targetHight = Heights.inches_4_7.rawValue
        case .inches_5_5:
            targetHight = Heights.inches_5_5.rawValue
        }
        return deviceHeight <= targetHight
    }
    
   public  func screenSizeInPixels() -> CGSize {
        let screen = UIScreen.main
        let height = screen.nativeBounds.size.height
        let width = screen.nativeBounds.size.width
        return CGSize(width: width, height: height)
    }
    
    public func screenSizeInPoints() -> CGSize {
        let screen = UIScreen.main
        let height = screen.bounds.size.height
        let width = screen.bounds.size.width
        return CGSize(width: width, height: height)
    }
    
    public func isPhone() -> Bool {
        return isSizeOrSmaller(.inches_5_5)
    }
    
    // MARK: - Private
    
    private enum Heights: CGFloat {
        case inches_3_5 = 480
        case inches_4 = 568
        case inches_4_7 = 667
        case inches_5_5 = 736
    }
    
    // Returns the screen dimentions in portrait reguardless of the current orientation
    private func deviceRect() -> CGRect {
        let screenSize = screenSizeInPoints()
        if screenSize.height > screenSize.width {
            return CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
        } else {
            return CGRect(x: 0, y: 0, width: screenSize.height, height: screenSize.width)
        }
    }
    
}
