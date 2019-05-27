//
//  AutoNavigationController.swift
//  AugmentKitDemo
//
//  Created by Marvin Scanlon on 5/26/19.
//  Copyright © 2019 Tenth Letter Made, LLC. All rights reserved.
//

import UIKit

class AutoNavigationController: UINavigationController {
    
    var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()

        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true, block: { [weak self] aTimer in
            let randomOption = Int.random(in: 0..<5)
            switch randomOption {
            case 0:
                self?.popToRootViewController(animated: true)
            case 1:
                if let newVC = self?.storyboard?.instantiateViewController(withIdentifier: "vcIdentifier1") {
                    self?.pushViewController(newVC, animated: true)
                }
            case 2:
                if let newVC = self?.storyboard?.instantiateViewController(withIdentifier: "vcIdentifier2") {
                    self?.pushViewController(newVC, animated: true)
                }
            case 3:
                if let newVC = self?.storyboard?.instantiateViewController(withIdentifier: "vcIdentifier3") {
                    self?.pushViewController(newVC, animated: true)
                }
            case 4:
                if let newVC = self?.storyboard?.instantiateViewController(withIdentifier: "vcIdentifier4") {
                    self?.pushViewController(newVC, animated: true)
                }
            default:
                break
            }
        })
    }
    
    deinit {
        timer?.invalidate()
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
