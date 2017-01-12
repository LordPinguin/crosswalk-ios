// Copyright (c) 2014 Intel Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation

open class XWalkExtensionFactory : NSObject {
    fileprivate struct XWalkExtensionProvider {
        let bundle: Bundle
        let className: String
    }
    fileprivate var extensions: Dictionary<String, XWalkExtensionProvider> = [:]
    fileprivate class var singleton : XWalkExtensionFactory {
        struct single {
            static let instance : XWalkExtensionFactory = XWalkExtensionFactory(path: nil)
        }
        return single.instance
    }

    fileprivate override init() {
        super.init()
        register("Extension.load",  cls: XWalkExtensionLoader.self)
    }
    fileprivate convenience init(path: String?) {
        self.init()
        if let dir = path ?? Bundle.main.privateFrameworksPath {
            self.scan(dir)
        }
    }

    fileprivate func scan(_ path: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) == true {
            for i in try! fm.contentsOfDirectory(atPath: path) {
                let name:NSString = i as NSString
                if name.pathExtension == "framework" {
                    let bundlePath = NSString(string: path).appendingPathComponent(name as String)
                    if let bundle = Bundle(path: bundlePath) {
                        scanBundle(bundle)
                    }
                }
            }
            return true
        }
        return false
    }

    fileprivate func scanBundle(_ bundle: Bundle) -> Bool {
        var dict: NSDictionary?
        let key: String = "XWalkExtensions"
        if let plistPath = bundle.path(forResource: "extensions", ofType: "plist") {
            let rootDict = NSDictionary(contentsOfFile: plistPath)
            dict = rootDict?.value(forKey: key) as? NSDictionary;
        } else {
            dict = bundle.object(forInfoDictionaryKey: key) as? NSDictionary
        }

        if let info = dict {
            let e = info.keyEnumerator()
            while let name = e.nextObject() as? String {
                if let className = info[name] as? String {
                    if extensions[name] == nil {
                        extensions[name] = XWalkExtensionProvider(bundle: bundle, className: className)
                    } else {
                        print("WARNING: duplicated extension name '\(name)'")
                    }
                } else {
                    print("WARNING: bad class name '\(info[name])'")
                }
            }
            return true
        }
        return false
    }

    fileprivate func register(_ name: String, cls: AnyClass) -> Bool {
        if extensions[name] == nil {
            let bundle = Bundle(for: cls)
            var className = cls.description()
            className = (className as NSString).pathExtension.isEmpty ? className : (className as NSString).pathExtension
            extensions[name] = XWalkExtensionProvider(bundle: bundle, className: className)
            return true
        }
        return false
    }

    fileprivate func getClass(_ name: String) -> AnyClass? {
        if let src = extensions[name] {
            // Load bundle
            if !src.bundle.isLoaded {
                let error : NSErrorPointer? = nil
                do {
                    try src.bundle.loadAndReturnError()
                } catch let error1 as NSError {
                    error??.pointee = error1
                    print("ERROR: Can't load bundle '\(src.bundle.bundlePath)'")
                    return nil
                }
            }

            var classType: AnyClass? = src.bundle.classNamed(src.className)
            if classType != nil {
                // FIXME: Never reach here because the bundle in build directory was loaded in simulator.
                return classType
            }
            // FIXME: workaround the problem
            // Try to get the class with the barely class name (for objective-c written class)
            classType = NSClassFromString(src.className)
            if classType == nil {
                // Try to get the class with its framework name as prefix (for swift written class)
                let classNameWithBundlePrefix = ((src.bundle.executablePath as NSString?)?.lastPathComponent)! + "." + src.className
                classType = NSClassFromString(classNameWithBundlePrefix)
            }
            if classType == nil {
                print("ERROR: Failed to get class:'\(src.className)' from bundle:'\(src.bundle.bundlePath)'")
                return nil;
            }
            return classType
        }
        print("ERROR: There's no class named:'\(name)' registered as extension")
        return nil
    }

    fileprivate func createExtension(_ name: String, initializer: Selector, arguments: [AnyObject]) -> AnyObject? {
        if let cls: AnyClass = getClass(name) {
            if class_respondsToSelector(cls, initializer) {
                if method_getNumberOfArguments(class_getInstanceMethod(cls, initializer)) <= UInt32(arguments.count) + 2 {
                    return XWalkInvocation.construct(cls, initializer: initializer, arguments: arguments) as AnyObject?
                }
                print("ERROR: Too few arguments to initializer '\(initializer.description)'.")
            } else {
                print("ERROR: Initializer '\(initializer.description)' not found in class '\(cls.description())'.")
            }
        } else {
            print("ERROR: Extension '\(name)' not found")
        }
        return nil
    }

    open class func register(_ name: String, cls: AnyClass) -> Bool {
        return XWalkExtensionFactory.singleton.register(name, cls: cls)
    }
    open class func createExtension(_ name: String) -> AnyObject? {
        return XWalkExtensionFactory.singleton.createExtension(name, initializer: "init", arguments: [])
    }
    open class func createExtension(_ name: String, initializer: Selector, arguments: [AnyObject]) -> AnyObject? {
        return XWalkExtensionFactory.singleton.createExtension(name, initializer: initializer, arguments: arguments)
    }
    open class func createExtension(_ name: String, initializer: Selector, varargs: AnyObject...) -> AnyObject? {
        return XWalkExtensionFactory.singleton.createExtension(name, initializer: initializer, arguments: varargs)
    }
}
