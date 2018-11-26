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
    
    let header = ["Authorization": "Bearer eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiIxMjIiLCJhdXRoIjoiUk9MRV9VU0VSIiwiZXhwIjoyNzQ2MzIxNjczN30.8tUlxdK4W35pQLG30D_sg10lzMYMIXLd3qYCKMODLIkAnLrPsRu6CjvahoH9j2IWrFPQMcNqBewF0NEAhJzQ-w",
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
    
    func stompClientDidOpenSocket(client: StompClient!) {
        print()
    }
    
    
    func stompClientDidDisconnect(client: StompClient!) {
        print()
    }
    
    func stompClientDidConnect(client: StompClient!) {
        print()
        client.subcribe(destination: "/user/122/topic/public", withHeader: header) { jsonString, header in
            print(jsonString)
            
        }
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
