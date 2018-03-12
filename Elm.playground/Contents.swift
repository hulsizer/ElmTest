//: Playground - noun: a place where people can play

import UIKit
import PlaygroundSupport

typealias VoidClosure = ()->()

// MARK - Architecture

protocol Subscription {
    func unregister()
}

struct BatchSubscription: Subscription {
    var subscriptions: [Subscription] = []
    
    func unregister() {
        for subscription in subscriptions {
            subscription.unregister()
        }
    }
}

struct Command<A> {
    typealias Element = A
    var interpret: ((@escaping (A)->()) -> ())
}

protocol Model {
    associatedtype Message: Equatable
    mutating func send(_: Message) -> [Command<Message>]
}

class Driver<ModelType> where ModelType: Model {
    private(set) var model: ModelType {
        didSet {
            updateSubscriptions(model: self.model)
            print("Model Update: \(self.model)")
        }
    }
    
    typealias SubscriptionGenerator = (Driver<ModelType>, ModelType) -> (Subscription)
    private var subscriptionGenerator: SubscriptionGenerator?
    private var subscription: Subscription? = nil
    
    public init(_ initial: ModelType, subscriptions: SubscriptionGenerator? = nil) {
        self.model = initial
        self.subscriptionGenerator = subscriptions
        self.subscription = subscriptions?(self, model)
    }
    
    func send(message: ModelType.Message) {
        let commands = model.send(message)
        for command in commands {
            interpret(command: command)
        }
    }
    
    func asyncSend(message: ModelType.Message) {
        DispatchQueue.main.async {
            self.send(message: message)
        }
    }
    
    func interpret(command: Command<ModelType.Message>) {
        command.interpret { [weak self] message in
            self?.asyncSend(message: message)
        }
    }
    
    func updateSubscriptions(model: ModelType) {
        subscription?.unregister()
        subscription = subscriptionGenerator?(self, model)
    }
}

// Mark: - Modules

extension Timer {
    
    struct TimerSubscription: Subscription {
        
        let timer: Timer
        init(duration: TimeInterval, callback: @escaping VoidClosure) {
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: true, block: { (timer) in
                callback()
            })
        }
        
        func unregister() {
            timer.invalidate()
        }
    }
    
    static func every(_ duration: TimeInterval, callback: @escaping VoidClosure) -> Subscription {
        return TimerSubscription(duration: duration, callback: callback)
    }
}

class HTTP {
    
    struct Request<A> {
        let url: URL
        let decode: (Data?) -> (A)
    }
    
    static func send<A>(_ request: HTTP.Request<A>) -> Command<A> {
        return Command(interpret: { callback in
            URLSession.shared.dataTask(with: request.url, completionHandler: { (data, response, error) in
                callback(request.decode(data))
            }).resume()
        })
    }
}

class SaveManager {
    
    static let SaveNotification = NSNotification.Name(rawValue: "SaveNotification")
    
    struct SaveSubscription: Subscription {
        
        let token: NSObjectProtocol
        init(id: String, callback: (@escaping (String, Bool) -> ())) {
            self.token = NotificationCenter.default.addObserver(forName: SaveNotification, object: id, queue: .main) { (notification) in
                guard let isSaved  = notification.userInfo?["isSaved"] as? Bool else {
                    return
                }
                callback(id, isSaved)
            }
        }
        
        func unregister() {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    static let shared = SaveManager()
    var saves: [String] = []
    
    //THIS SEEMS WRONG
    //DO I NEED TO MAINTAIN STATE ON THE MANAGER OR DOES EACH MODEL
    //HAVE ITS OWN STATE, AND THE SAVE COMMAND JUST SENDS A NOTIFICATION
    func save(id: String) {
        guard self.saves.index(of: id) == nil else {
            return
        }
        
        self.saves.append(id)
        NotificationCenter.default.post(name: SaveManager.SaveNotification, object: id, userInfo: ["isSaved": true])
    }
    
    func unsave(id: String) {
        guard let index = self.saves.index(of: id) else {
            return
        }
        
        self.saves.remove(at: index)
        NotificationCenter.default.post(name: SaveManager.SaveNotification, object: id, userInfo: ["isSaved": false])
    }
    
    func save<A>(id: String, decode: @escaping (String, Bool) -> (A)) -> Command<A> {
        let url = URL(string: "https://www.google.com")!
        
        let request = HTTP.Request(url: url) { [weak self] (data) -> (A) in
            self?.save(id: id)
            return decode(id, true)
        }
        
        return HTTP.send(request)
    }
    
    func unsave<A>(id: String, decode: @escaping (String, Bool) -> (A)) -> Command<A> {
        let url = URL(string: "https://www.google.com")!
        
        let request = HTTP.Request(url: url) { [weak self] (data) -> (A) in
            self?.unsave(id: id)
            return decode(id, false)
        }
        
        
        return HTTP.send(request)
    }
    
    static func register(id: String, onChange: @escaping (String, Bool) -> ()) -> SaveSubscription {

        let subscription = SaveSubscription(id: id, callback: onChange)
        return subscription
    }
}

// MARK: - Helpers

func getNewName(topic: String) -> Command<NameModel.Message> {
    let url = URL(string: "https://www.google.com")!
    
    let request = HTTP.Request(url: url) { (data) -> (NameModel.Message) in
        return .nameChange("Andrew")
    }
    
    return HTTP.send(request)
}

extension DispatchQueue {

    func delay(_ delay:Double, closure:@escaping ()->()) {
        DispatchQueue.main.asyncAfter(
            deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: closure)
    }
}

// MARK - Application

struct NameModel: Model {
    
    enum Message: Equatable {
        case nameChange(String)
        case makeAndrew
        case save(String)
        case unsave(String)
        case saveChanged(String, Bool)
        static func ==(lhs: NameModel.Message, rhs: NameModel.Message) -> Bool {
            switch (lhs, rhs) {
            case (.nameChange(let lhsTitle), .nameChange(let rhsTitle)):
                return lhsTitle == rhsTitle
            case (.makeAndrew, .makeAndrew):
                return true
            case (.save(let lhsTitle), .save(let rhsTitle)):
                return lhsTitle == rhsTitle
            case (.unsave(let lhsTitle), .unsave(let rhsTitle)):
                return lhsTitle == rhsTitle
            case (.saveChanged(let lhsTitle, let lhsBool), .saveChanged(let rhsTitle, let rhsBool)):
                return lhsTitle == rhsTitle && lhsBool == rhsBool
            default:
                return false
            }
        }
    }
    
    var title: String
    var saves: [String]
    
    @discardableResult
    mutating func send(_ message: NameModel.Message) -> [Command<NameModel.Message>] {
        switch message {
        case .nameChange(let name):
            self.title = name
            return []
        case .makeAndrew:
            self.title = "loading name"
            return [getNewName(topic: "Andrew")]
        case .save(let id):
            return [SaveManager.shared.save(id: id, decode: { (id, isSaved) in
                return .saveChanged(id, isSaved)
            })]
        case .unsave(let id):
            return [SaveManager.shared.unsave(id: id, decode: { (id, isSaved) in
                return .saveChanged(id, isSaved)
            })]
        case .saveChanged(let id, let isSaved):
            if let index = self.saves.index(of: id) {
                if !isSaved {
                    self.saves.remove(at: index)
                }
            } else {
                if isSaved {
                    self.saves.append(id)
                }
            }
            
            return []
        }
    }
}

var model = NameModel(title: "Matt", saves: [])
let driver = Driver(model) { (driver, model) -> Subscription in
    
    var subscriptions: [Subscription] = []
    
    for save in model.saves {
        let subscription = SaveManager.register(id: save) { id, isSaved in
            driver.send(message: .saveChanged(id, isSaved))
        }
        subscriptions.append(subscription)
    }
    
    return BatchSubscription(subscriptions: subscriptions)
}

driver.send(message: .save("14"))

DispatchQueue.main.delay(1) {
    driver.send(message: .save("16"))
}

DispatchQueue.main.delay(2) {
    driver.send(message: .unsave("14"))
}

PlaygroundPage.current.needsIndefiniteExecution = true
