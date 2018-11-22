//
//  ViewController.swift
//  StompClient
//
//  Created by qhquanghuy96@gmail.com on 11/21/2018.
//  Copyright (c) 2018 qhquanghuy96@gmail.com. All rights reserved.
//

import UIKit
import StompClient
class ViewController: UIViewController {

    
    let client = StompClient()
    
    let header = ["Authorization": "Bearer eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJtdSIsImF1dGgiOiJST0xFX1VTRVIiLCJleHAiOjE1NDI4NzI3MTZ9.3-fy4nV0USANUoP3dBn1EAhQ1snqWiTkfVGbSh6zqYU4X5WabmRewaP_-SUqO2CcS2PbXe9egS81-FVR5gY-Rw",
                  "accept-version": "1.1"
                  ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        let req = URL.init(string: "http://10.10.0.20:8000/ws/websocket")
            .map { URLRequest.init(url: $0) }
        
        client.openSocket(request: req!,
                          delegate: self,
                          connectionHeaders: header)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

extension ViewController: StompClientDelegate {
    func stompClient(client: StompClient!, didReceiveMessageWithJSONBody jsonBody: String?, withHeader header: [String : String]?, withDestination destination: String) {
        print(jsonBody)
    }
    
    func stompClientDidOpenSocket(client: StompClient!) {
        print()
    }
    
    
    func stompClientDidDisconnect(client: StompClient!) {
        print()
    }
    
    func stompClientDidConnect(client: StompClient!) {
        print()
        client.subcribe(destination: "/user/mu/topic/public", withHeader: header)
//        client.subcribe(destination: "/topic/public/user", withHeader: header)
    }
    
    func serverDidSendReceipt(client: StompClient!, withReceiptId receiptId: String) {
        print(receiptId)
    }
    
    func serverDidSendError(client: StompClient!, withErrorMessage description: String, detailedErrorMessage message: String?) {
        print(description)
    }
    
    func serverDidSendPing() {
        
    }
    
    
}
