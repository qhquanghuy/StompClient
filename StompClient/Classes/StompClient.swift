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

private func decodeJSONStringResponse<T: Decodable>(jsonString: String) -> T? {
    let decoder = JSONDecoder()
    do {
        return try jsonString.data(using: .utf8).map { try decoder.decode(T.self, from: $0) }
    } catch {
        print("JSON Decoding error: \(error)")
    }
    return nil
}

// Fundamental Protocols
public protocol StompClientDelegate {
    func stompClientDidOpenSocket(client: StompClient!)
    func stompClientDidDisconnect(client: StompClient!)
    func stompClientDidConnect(client: StompClient!)
    func serverDidSendReceipt(client: StompClient!, withReceiptId receiptId: String)
    func serverDidSendError(client: StompClient!, withErrorMessage description: String, detailedErrorMessage message: String?)
    func serverDidSendPing()
}

public class StompClient: NSObject, WebSocketDelegate {
    
    public typealias ResponseHandler = (String?, [String: String]) -> ()
    public typealias CodableResponseHandler<T: Decodable> = (T, [String: String]) -> ()
    
    var socket: WebSocket?
    var sessionId: String?
    var userId: String?
    var delegate: StompClientDelegate?
    var connectionHeaders: [String: String]?
    public private(set) var status: ClientStatus = .disconnected
    public var certificateCheckEnabled = true
    private var urlRequest: URLRequest?
    private var handlers: [String: ResponseHandler] = [:]
    
    public func send<T: Encodable>(data: T, to destination: String) {
        let encoder = JSONEncoder()
        do {
            let bytes = try encoder.encode(data)
            let jsonString = String(data: bytes, encoding: .utf8)
            
            let header = [StompCommands.commandHeaderContentType:"application/json;charset=UTF-8"]
            sendMessage(message: jsonString!, toDestination: destination, withHeaders: header, withReceipt: nil)
        } catch {
            print("\(#function): error serializing JSON: \(error)")
        }
        
    }
    
    public func openSocket(request: URLRequest, delegate: StompClientDelegate, connectionHeaders: [String: String]? = nil) {
        self.connectionHeaders = connectionHeaders
        self.delegate = delegate
        self.urlRequest = request
        
        self.openSocket()
        
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
        
        self.handlers.removeAll()
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
    
    
  
   
    private func sendFrame(command: String?, header: [String: String]?, body: String?) {
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
            
            if let body = body {
                frameString += "\n"
                frameString += body
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
    
    
    private func receiveFrame(command: String, headers: [String: String], body: String?) {
        if command == StompCommands.responseFrameConnected {
            // Connected
            self.status = .connected
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
            let destination = self.destinationFromHeader(header: headers)
            let handler = self.handlers[destination]
            handler?(body, headers)
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
        sendFrame(command: StompCommands.commandSend, header: headersToSend, body: message)
    }
    
    /*
     Main Subscribe Method with topic name
     */
    
    private func addHandler(destination: String, handler: @escaping ResponseHandler) {
        self.handlers[destination] = handler
    }
    
    private func _subcribe(destination: String,
                           ackMode: StompAckMode = .autoMode,
                           completion: () -> ()) {
        precondition(!destination.isEmpty, "cannot subcribe empty destination")
        
        self.status = .subcribed
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
        
        completion()
        
        self.sendFrame(command: StompCommands.commandSubscribe, header: headers, body: nil)
    }
    
    
    
    private func _subcribe(destination: String,
                         withHeader header: [String: String],
                         completion: () -> ()) {
        
        precondition(!destination.isEmpty, "cannot subcribe empty destination")
        
        self.status = .subcribed
        var headerToSend = header
        headerToSend[StompCommands.commandHeaderDestination] = destination
        if headerToSend[StompCommands.commandHeaderDestinationId] == nil {
            headerToSend[StompCommands.commandHeaderDestinationId] = "sub-\(destination)"
        }
        
        completion()
        sendFrame(command: StompCommands.commandSubscribe, header: headerToSend, body: nil)
    }
    
    public func subcribe(destination: String,
                         ackMode: StompAckMode = .autoMode,
                         with handler: @escaping ResponseHandler) {
        
        _subcribe(destination: destination, ackMode: ackMode) {
            self.addHandler(destination: destination, handler: handler)
        }
    }
    
    public func subcribe(destination: String,
                         withHeader header: [String: String],
                         with handler: @escaping ResponseHandler) {
        
        _subcribe(destination: destination, withHeader: header) {
            self.addHandler(destination: destination, handler: handler)
        }
    }
    
    
    public func subcribeDecodable<T: Decodable>(destination: String,
                                                ackMode: StompAckMode = .autoMode,
                                                with handler: @escaping CodableResponseHandler<T>) {
        
        _subcribe(destination: destination, ackMode: ackMode) {
            self.addHandler(destination: destination) { jsonString, header in
                
                guard let json = jsonString, let data: T = decodeJSONStringResponse(jsonString: json)
                    else { return }
                
                handler(data, header)
                
            }
        }
    }
    
    public func subcribeDecodable<T: Decodable>(destination: String,
                                                withHeader header: [String: String],
                                                with handler: @escaping CodableResponseHandler<T>) {
        
        _subcribe(destination: destination, withHeader: header) {
            self.addHandler(destination: destination) { jsonString, header in
                guard let json = jsonString, let data: T = decodeJSONStringResponse(jsonString: json)
                    else { return }
                
                handler(data, header)
            }
        }
        
    }
    
 
    /*
     Main Unsubscribe Method with topic name
     */
    public func unsubscribe(destination: String) {
        self.status = .connected
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderDestinationId] = destination
        self.handlers[destination] = nil
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
        self.status = .disconnected
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
        if self.status == .disconnected {
            self.openSocket(request: request, delegate: delegate, connectionHeaders: connectionHeaders)
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
        self.connect()
        DispatchQueue.main.async(execute: { [weak self] in
            self?.delegate?.stompClientDidOpenSocket(client: self)
        })
        
    }
    
    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        
        if let err = error {
            self.status = .disconnected
            print(err)
        }
        
        DispatchQueue.main.async(execute: { [weak self] in
            self?.delegate?.stompClientDidDisconnect(client: self)
        })
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
extension StompClient {
    public enum ClientStatus {
        case disconnected
        case connectedSocket //connected to the server socket
        case connected //server accept connect command
        case subcribed //subcribe to a source
    }
}
