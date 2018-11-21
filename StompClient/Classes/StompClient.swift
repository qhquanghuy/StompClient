import Starscream

struct StompCommands {
    // Basic Commands
    static let commandConnect = "CONNECT"
    static let commandSend = "SEND"
    static let commandSubscribe = "SUBSCRIBE"
    static let commandUnsubscribe = "UNSUBSCRIBE"
    static let commandBegin = "BEGIN"
    static let commandCommit = "COMMIT"
    static let commandAbort = "ABORT"
    static let commandAck = "ACK"
    static let commandDisconnect = "DISCONNECT"
    static let commandPing = "\n"
    
    static let controlChar = String(format: "%C", arguments: [0x00])
    
    // Ack Mode
    static let ackClient = "client"
    static let ackAuto = "auto"
    // Header Commands
    static let commandHeaderReceipt = "receipt"
    static let commandHeaderDestination = "destination"
    static let commandHeaderDestinationId = "id"
    static let commandHeaderContentLength = "content-length"
    static let commandHeaderContentType = "content-type"
    static let commandHeaderAck = "ack"
    static let commandHeaderTransaction = "transaction"
    static let commandHeaderMessageId = "message-id"
    static let commandHeaderSubscription = "subscription"
    static let commandHeaderDisconnected = "disconnected"
    static let commandHeaderHeartBeat = "heart-beat"
    static let commandHeaderAcceptVersion = "accept-version"
    // Header Response Keys
    static let responseHeaderSession = "session"
    static let responseHeaderReceiptId = "receipt-id"
    static let responseHeaderErrorMessage = "message"
    // Frame Response Keys
    static let responseFrameConnected = "CONNECTED"
    static let responseFrameMessage = "MESSAGE"
    static let responseFrameReceipt = "RECEIPT"
    static let responseFrameError = "ERROR"
}

public enum StompAckMode {
    case autoMode
    case clientMode
}

// Fundamental Protocols
public protocol StompClientDelegate {
    func stompClientDidOpenSocket(client: StompClient!)
    func stompClient(client: StompClient!, didReceiveMessageWithJSONBody jsonBody: AnyObject?, withHeader header:[String:String]?, withDestination destination: String)
    
    func stompClientDidDisconnect(client: StompClient!)
    func stompClientDidConnect(client: StompClient!)
    func serverDidSendReceipt(client: StompClient!, withReceiptId receiptId: String)
    func serverDidSendError(client: StompClient!, withErrorMessage description: String, detailedErrorMessage message: String?)
    func serverDidSendPing()
}

public class StompClient: NSObject, WebSocketDelegate {
    
    
    var socket: WebSocket?
    var sessionId: String?
    var userId: String?
    var delegate: StompClientDelegate?
    var connectionHeaders: [String: String]?
    
    
    var randomString: String {
        var str = "adklsfjeioqueiojlad,.znxcmv,noieuwrdalsfj"
        str.shuffled()
        
        return str
    }
    
    public var connection: Bool = false
    public var certificateCheckEnabled = true
    private var urlRequest: URLRequest?
    
    public func sendJSONForDict(dict: AnyObject, toDestination destination: String) {
        do {
            let theJSONData = try JSONSerialization.data(withJSONObject: dict, options: JSONSerialization.WritingOptions())
            let theJSONText = String(data: theJSONData, encoding: String.Encoding.utf8)
            //print(theJSONText!)
            let header = [StompCommands.commandHeaderContentType:"application/json;charset=UTF-8"]
            sendMessage(message: theJSONText!, toDestination: destination, withHeaders: header, withReceipt: nil)
        } catch {
            print("error serializing JSON: \(error)")
        }
    }
    
    public func openSocket(request: URLRequest, delegate: StompClientDelegate) {
        self.delegate = delegate
        self.urlRequest = request
        // Opening the socket
        openSocket()
    }
    
    public func openSocket(request: URLRequest, delegate: StompClientDelegate, connectionHeaders: [String: String]?) {
        self.connectionHeaders = connectionHeaders
        openSocket(request: request, delegate: delegate)
        self.connection = true
    }
    
    private func openSocket() {
        if socket == nil || socket?.isConnected == true {
            if certificateCheckEnabled == true {
                self.socket = WebSocket(request: urlRequest!)
            } else {
                self.socket = WebSocket(request: urlRequest!, protocols: [])
                self.socket?.disableSSLCertValidation = true
            }
            
            socket!.delegate = self
            socket!.connect()
            
        }
    }
    
    private func closeSocket(){
        if let delegate = delegate {
            DispatchQueue.main.async(execute: {
                delegate.stompClientDidDisconnect(client: self)
                if self.socket != nil {
                    // Close the socket
                    self.socket!.disconnect()
                    self.socket!.delegate = nil
                    self.socket = nil
                }
            })
        }
    }
    
    /*
     Main Connection Method to open socket
     */
    private func connect() {
        if socket?.isConnected == true {
            // at the moment only anonymous logins
            self.sendFrame(command: StompCommands.commandConnect, header: connectionHeaders, body: nil)
        } else {
            self.openSocket()
        }
    }
    
    
  
   
    private func sendFrame(command: String?, header: [String: String]?, body: AnyObject?) {
        if socket?.isConnected == true {
            var frameString = ""
            if command != nil {
                frameString = command! + "\n"
            }
            
            if let header = header {
                for (key, value) in header {
                    frameString += key
                    frameString += ":"
                    frameString += value
                    frameString += "\n"
                }
            }
            
            if let body = body as? String {
                frameString += "\n"
                frameString += body
            } else if let _ = body as? NSData {
                
            }
            
            if body == nil {
                frameString += "\n"
            }
            
            frameString += StompCommands.controlChar
            
            if socket?.isConnected == true {
                socket?.write(string: frameString)
            } else {
                if let delegate = delegate {
                    DispatchQueue.main.async(execute: {
                        delegate.stompClientDidDisconnect(client: self)
                    })
                }
            }
        }
    }
    
    private func destinationFromHeader(header: [String: String]) -> String {
        for (key, _) in header {
            if key == "destination" {
                let destination = header[key]!
                return destination
            }
        }
        return ""
    }
    
    private func dictForJSONString(jsonStr: String?) -> AnyObject? {
        if let jsonStr = jsonStr {
            do {
                if let data = jsonStr.data(using: String.Encoding.utf8) {
                    let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                    return json as AnyObject
                }
            } catch {
                print("error serializing JSON: \(error)")
            }
        }
        return nil
    }
    
    private func receiveFrame(command: String, headers: [String: String], body: String?) {
        if command == StompCommands.responseFrameConnected {
            // Connected
            if let sessId = headers[StompCommands.responseHeaderSession] {
                sessionId = sessId
            }
           
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.stompClientDidConnect(client: self)
                })
            }
        } else if command == StompCommands.responseFrameMessage {   // Message comes to this part
            // Response
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.stompClient(client: self, didReceiveMessageWithJSONBody: self.dictForJSONString(jsonStr: body), withHeader: headers, withDestination: self.destinationFromHeader(header: headers))
                })
            }
        } else if command == StompCommands.responseFrameReceipt {   //
            // Receipt
            if let delegate = delegate {
                if let receiptId = headers[StompCommands.responseHeaderReceiptId] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendReceipt(client: self, withReceiptId: receiptId)
                    })
                }
            }
        } else if command.count == 0 {
            // Pong from the server
            socket?.write(string: StompCommands.commandPing)
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.serverDidSendPing()
                })
            }
        } else if command == StompCommands.responseFrameError {
            // Error
            if let delegate = delegate {
                if let msg = headers[StompCommands.responseHeaderErrorMessage] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendError(client: self, withErrorMessage: msg, detailedErrorMessage: body)
                    })
                }
            }
        }
    }
    
    public func sendMessage(message: String, toDestination destination: String, withHeaders headers: [String: String]?, withReceipt receipt: String?) {
        var headersToSend = [String: String]()
        if let headers = headers {
            headersToSend = headers
        }
        
        // Setting up the receipt.
        if let receipt = receipt {
            headersToSend[StompCommands.commandHeaderReceipt] = receipt
        }
        
        headersToSend[StompCommands.commandHeaderDestination] = destination
        
        // Setting up the content length.
        let contentLength = message.utf8.count
        headersToSend[StompCommands.commandHeaderContentLength] = "\(contentLength)"
        
        // Setting up content type as plain text.
        if headersToSend[StompCommands.commandHeaderContentType] == nil {
            headersToSend[StompCommands.commandHeaderContentType] = "text/plain"
        }
        sendFrame(command: StompCommands.commandSend, header: headersToSend, body: message as AnyObject)
    }
    
    /*
     Main Connection Check Method
     */
    public func isConnected() -> Bool{
        return connection
    }
    
    /*
     Main Subscribe Method with topic name
     */
    public func subscribe(destination: String) {
        connection = true
        subcribe(destination: destination, ackMode: .autoMode)
    }
    
    public func subcribe(destination: String, ackMode: StompAckMode) {
        var ack = ""
        switch ackMode {
        case StompAckMode.clientMode:
            ack = StompCommands.ackClient
        default:
            ack = StompCommands.ackAuto
        }
        var headers = [StompCommands.commandHeaderDestination: destination, StompCommands.commandHeaderAck: ack, StompCommands.commandHeaderDestinationId: ""]
        if destination != "" {
            headers = [StompCommands.commandHeaderDestination: destination, StompCommands.commandHeaderAck: ack, StompCommands.commandHeaderDestinationId: destination]
        }
        self.sendFrame(command: StompCommands.commandSubscribe, header: headers, body: nil)
    }
    
    public func subcribe(destination: String, withHeader header: [String: String]) {
        var headerToSend = header
        headerToSend[StompCommands.commandHeaderDestination] = destination
        if headerToSend[StompCommands.commandHeaderDestinationId] == nil {
            headerToSend[StompCommands.commandHeaderDestinationId] = "sub-\(self.randomString)"
        }
        sendFrame(command: StompCommands.commandSubscribe, header: headerToSend, body: nil)
    }
    
    /*
     Main Unsubscribe Method with topic name
     */
    public func unsubscribe(destination: String) {
        connection = false
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderDestinationId] = destination
        sendFrame(command: StompCommands.commandUnsubscribe, header: headerToSend, body: nil)
    }
    
    public func begin(transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandBegin, header: headerToSend, body: nil)
    }
    
    public func commit(transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandCommit, header: headerToSend, body: nil)
    }
    
    public func abort(transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandAbort, header: headerToSend, body: nil)
    }
    
    public func ack(messageId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        sendFrame(command: StompCommands.commandAck, header: headerToSend, body: nil)
    }
    
    public func ack(messageId: String, withSubscription subscription: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        headerToSend[StompCommands.commandHeaderSubscription] = subscription
        sendFrame(command: StompCommands.commandAck, header: headerToSend, body: nil)
    }
    
    /*
     Main Disconnection Method to close the socket
     */
    public func disconnect() {
        connection = false
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandDisconnect] = String(Int(NSDate().timeIntervalSince1970))
        sendFrame(command: StompCommands.commandDisconnect, header: headerToSend, body: nil)
        // Close the socket to allow recreation
        self.closeSocket()
    }
    
    // Reconnect after one sec or arg, if reconnect is available
    // TODO: MAKE A VARIABLE TO CHECK RECONNECT OPTION IS AVAILABLE OR NOT
    public func reconnect(request: URLRequest, delegate: StompClientDelegate, connectionHeaders: [String: String] = [String: String](), time: Double = 1.0, exponentialBackoff: Bool = true){
        if #available(iOS 10.0, *) {
            Timer.scheduledTimer(withTimeInterval: time, repeats: true, block: { _ in
                self.reconnectLogic(request: request, delegate: delegate
                    , connectionHeaders: connectionHeaders)
            })
        } else {
            // Fallback on earlier versions
            // Swift >=3 selector syntax
            //            Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.reconnectFallback), userInfo: nil, repeats: true)
            print("Reconnect Feature has no support for below iOS 10, it is going to be available soon!")
        }
    }
    //    @objc func reconnectFallback() {
    //        reconnectLogic(request: request, delegate: delegate, connectionHeaders: connectionHeaders)
    //    }
    
    private func reconnectLogic(request: URLRequest, delegate: StompClientDelegate, connectionHeaders: [String: String] = [String: String]()){
        // Check if connection is alive or dead
        if (!self.isConnected()){
            self.checkConnectionHeader(connectionHeaders: connectionHeaders) ? self.openSocket(request: request, delegate: delegate, connectionHeaders: connectionHeaders) : self.openSocket(request: request, delegate: delegate)
        }
    }
    
    private func checkConnectionHeader(connectionHeaders: [String: String] = [String: String]()) -> Bool{
        if (connectionHeaders.isEmpty){
            // No connection header
            return false
        } else {
            // There is a connection header
            return true
        }
    }
    
    // Autodisconnect with a given time
    public func autoDisconnect(time: Double){
        DispatchQueue.main.asyncAfter(deadline: .now() + time) {
            // Disconnect the socket
            self.disconnect()
        }
    }
    
    
    public func websocketDidConnect(socket: WebSocketClient) {
        print("WebSocket is connected")
        connect()
        DispatchQueue.main.async(execute: { [weak self] in
            self?.delegate?.stompClientDidOpenSocket(client: self)
        })
        
    }
    
    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        
        if let err = error {
            DispatchQueue.main.async(execute: { [weak self] in
                self?.delegate?.serverDidSendError(client: self,
                                                   withErrorMessage: err.localizedDescription,
                                                   detailedErrorMessage: err as? String)
            })
        } else {
            DispatchQueue.main.async(execute: { [weak self] in
                self?.delegate?.stompClientDidDisconnect(client: self)
            })
        }
    }
    
    public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        processString(string: text)
    }
    
    public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        String(data: data, encoding: .utf8).map(self.processString)
    }
    
    private func processString(string: String) {
        var contents = string.components(separatedBy: "\n")
        if contents.first == "" {
            contents.removeFirst()
        }
        
        if let command = contents.first {
            var headers = [String: String]()
            var body = ""
            var hasHeaders  = false
            
            contents.removeFirst()
            for line in contents {
                if hasHeaders == true {
                    body += line
                } else {
                    if line == "" {
                        hasHeaders = true
                    } else {
                        let parts = line.components(separatedBy: ":")
                        if let key = parts.first {
                            headers[key] = parts.last
                        }
                    }
                }
            }
            
            // Remove the garbage from body
            if body.hasSuffix("\0") {
                body = body.replacingOccurrences(of: "\0", with: "")
            }
            
            receiveFrame(command: command, headers: headers, body: body)
        }
    }
}
