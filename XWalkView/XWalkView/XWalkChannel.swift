// Copyright (c) 2014 Intel Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation
import WebKit

open class XWalkChannel : NSObject, WKScriptMessageHandler {
    open let name: String
    open var mirror: XWalkReflection!
    open var namespace: String = ""
    open weak var webView: XWalkView?
    open weak var thread: Thread?

    fileprivate var instances: [Int: AnyObject] = [:]
    fileprivate var userScript: WKUserScript?

    public init(webView: XWalkView) {
        struct seq{
            static var num: UInt32 = 0
        }

        self.webView = webView
        seq.num += 1
        self.name = "\(seq.num)"
        super.init()
        webView.configuration.userContentController.add(self, name: "\(self.name)")
    }

    open func bind(_ object: AnyObject, namespace: String, thread: Thread?) {
        self.namespace = namespace
        self.thread = thread ?? Thread.main

        mirror = XWalkReflection(cls: type(of: object))
        var script = XWalkStubGenerator(reflection: mirror).generate(name, namespace: namespace, object: object)
        let delegate = object as? XWalkDelegate
        script = delegate?.didGenerateStub?(script) ?? script

        userScript = webView?.injectScript(script)
        delegate?.didBindExtension?(self, instance: 0)
        instances[0] = object
    }

    open func destroyExtension() {
        if webView?.url != nil {
            evaluateJavaScript("delete \(namespace);", completionHandler:nil)
        }
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "\(name)")
        if userScript != nil {
            webView?.configuration.userContentController.removeUserScript(userScript!)
        }
        for (_, object) in instances {
            (object as? XWalkDelegate)?.didUnbindExtension?()
        }
        instances.removeAll(keepingCapacity: false)
    }

    open func userContentController(_ userContentController: WKUserContentController, didReceive didReceiveScriptMessage: WKScriptMessage) {
        let body = didReceiveScriptMessage.body as! [String: AnyObject]
        let instid = (body["instance"] as? NSNumber)?.intValue ?? 0
        let callid = body["callid"] as? NSNumber ?? NSNumber(value: 0 as Int)
        let args = [(callid as AnyObject)] + (body["arguments"] as? [AnyObject] ?? [])

        if let method = body["method"] as? String {
            // Invoke method
            if let object: AnyObject = instances[instid] {
                let delegate = object as? XWalkDelegate
                if delegate?.invokeNativeMethod != nil {
                    let selector = #selector(XWalkDelegate.invokeNativeMethod(_:arguments:))
                    XWalkInvocation.asyncCall(on: thread, target: object, selector: selector, arguments: [method, args])
                } else if mirror.hasMethod(method) {
                    XWalkInvocation.asyncCall(on: thread, target: object, selector: mirror.getMethod(method), arguments: args)
                } else {
                    print("ERROR: Method '\(method)' is not defined in class '\(type(of: object).description())'.")
                }
            } else {
                print("ERROR: Instance \(instid) does not exist.")
            }
        } else if let prop = body["property"] as? String {
            // Update property
            if let object: AnyObject = instances[instid] {
                let value: AnyObject = body["value"] ?? NSNull()
                let delegate = object as? XWalkDelegate
                if delegate?.setNativeProperty != nil {
                    let selector = #selector(XWalkDelegate.setNativeProperty(_:value:))
                    XWalkInvocation.asyncCall(on: thread, target: object, selector: selector, arguments: [prop, value])
                } else if mirror.hasProperty(prop) {
                    let selector = mirror.getSetter(prop)
                    if selector != "" {
                        XWalkInvocation.asyncCall(on: thread, target: object, selector: selector, arguments: [value])
                    } else {
                        print("ERROR: Property '\(prop)' is readonly.")
                    }
                } else {
                    print("ERROR: Property '\(prop)' is not defined in class '\(type(of: object).description())'.")
                }
            } else {
                print("ERROR: Instance \(instid) does not exist.")
            }
        } else if instid > 0 && instances[instid] == nil {
            // Create instance
            let ctor: AnyObject = instances[0]!
            let object: AnyObject = XWalkInvocation.construct(on: thread, class: type(of: ctor), initializer: mirror.constructor, arguments: args) as AnyObject
            instances[instid] = object
            (object as? XWalkDelegate)?.didBindExtension?(self, instance: instid)
            // TODO: shoud call releaseArguments
        } else if let object: AnyObject = instances[-instid] {
            // Destroy instance
            instances.removeValue(forKey: -instid)
            (object as? XWalkDelegate)?.didUnbindExtension?()
        } else if body["destroy"] != nil {
            destroyExtension()
        } else {
            // TODO: support user defined message?
            print("ERROR: Unknown message: \(body)")
        }
    }

    open func evaluateJavaScript(_ string: String, completionHandler: ((AnyObject?, NSError?)->Void)?) {
        // TODO: Should call completionHandler with an NSError object when webView is nil
        if Thread.isMainThread {
            webView?.evaluateJavaScript(string, completionHandler: completionHandler as! ((Any?, Error?) -> Void)?)
        } else {
            weak var weakSelf = self
            DispatchQueue.main.async {
                if let strongSelf = weakSelf {
                    strongSelf.webView?.evaluateJavaScript(string, completionHandler: completionHandler as! ((Any?, Error?) -> Void)?)
                }
            }
        }
    }
}
