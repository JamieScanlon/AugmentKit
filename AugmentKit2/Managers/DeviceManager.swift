//
//  DeviceManager.swift
//  AugmentKit2
//
//  Created by Jamie Scanlon on 7/15/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import UIKit

class DeviceManager {
    
    static var shared = DeviceManager()
    
    enum ScreenHeights: Int {
        case inches_3_5
        case inches_4
        case inches_4_7
        case inches_5_5
    }
    
    func isSize(_ height: ScreenHeights) -> Bool {
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
    
    func isSizeOrLarger(_ height: ScreenHeights) -> Bool {
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
    
    func isSizeOrSmaller(_ height: ScreenHeights) -> Bool {
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
    
    func screenSizeInPixels() -> CGSize {
        let screen = UIScreen.main
        let height = screen.nativeBounds.size.height
        let width = screen.nativeBounds.size.width
        return CGSize(width: width, height: height)
    }
    
    func screenSizeInPoints() -> CGSize {
        let screen = UIScreen.main
        let height = screen.bounds.size.height
        let width = screen.bounds.size.width
        return CGSize(width: width, height: height)
    }
    
    func isPhone() -> Bool {
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
