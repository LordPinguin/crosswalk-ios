// Copyright (c) 2014 Intel Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation

open class XWalkReflection : NSObject {
    fileprivate enum MemberType: UInt {
        case method = 1
        case getter
        case setter
        case constructor
    }
    fileprivate struct MemberInfo {
        init(cls: AnyClass) {
            self.cls = cls
        }
        init(cls: AnyClass, method: Method) {
            self.cls = cls
            self.method = method
        }
        init(cls: AnyClass, getter: Method, setter: Method) {
            self.cls = cls
            self.getter = getter
            self.setter = setter
        }
        var cls: AnyClass
        var method: Method? = nil
        var getter: Method? = nil
        var setter: Method? = nil
    }

    open let cls: AnyClass
    fileprivate var members: [String: MemberInfo] = [:]
    fileprivate var ctor: Method? = nil

    fileprivate let methodPrefix = "jsfunc_"
    fileprivate let getterPrefix = "jsprop_"
    fileprivate let setterPrefix = "setJsprop_"
    fileprivate let ctorPrefix = "initFromJavaScript:"

    public init(cls: AnyClass) {
        self.cls = cls
        super.init()
        enumerate({(name, type, method, cls) -> Bool in
            if type == MemberType.method {
                assert(self.members[name] == nil, "ambiguous method: \(name)")
                self.members[name] = MemberInfo(cls: cls, method: method)
            } else if type == MemberType.constructor {
                assert(self.ctor == nil, "ambiguous initializer")
                self.ctor = method
            } else {
                if self.members[name] == nil {
                    self.members[name] = MemberInfo(cls: cls)
                } else {
                    assert(self.members[name]!.method == nil, "name conflict: \(name)")
                }
                if type == MemberType.getter {
                    self.members[name]!.getter = method
                } else {
                    assert(type == MemberType.setter)
                    self.members[name]!.setter = method
                }
            }
            return true
        })
    }

    // Basic information
    open var allMembers: [String] {
        return members.keys.filter({(e)->Bool in return true})
    }
    open var allMethods: [String] {
        return members.keys.filter({(e)->Bool in return self.hasMethod(e)})
    }
    open var allProperties: [String] {
        return members.keys.filter({(e)->Bool in return self.hasProperty(e)})
    }
    open func hasMember(_ name: String) -> Bool {
        return members[name] != nil
    }
    open func hasMethod(_ name: String) -> Bool {
        return (members[name]?.method ?? nil) != nil
    }
    open func hasProperty(_ name: String) -> Bool {
        return (members[name]?.getter ?? nil) != nil
    }
    open func isReadonly(_ name: String) -> Bool {
        assert(hasProperty(name))
        return (members[name]?.setter ?? nil) == nil
    }

    // Fetching selectors
    open var constructor: Selector? {
        return method_getName(ctor)
    }
    open func getMethod(_ name: String) -> Selector {
        return method_getName(members[name]?.method ?? nil)
    }
    open func getGetter(_ name: String) -> Selector {
        return method_getName(members[name]?.getter ?? nil)
    }
    open func getSetter(_ name: String) -> Selector {
        return method_getName(members[name]?.setter ?? nil)
    }

    // TODO: enumerate instance methods of super class
    fileprivate func enumerate(_ callback: ((String, MemberType, Method, AnyClass)->Bool)) -> Bool {
        let methodList = class_copyMethodList(cls, nil);
        var mlist = methodList
        while mlist?.pointee != nil {
            let name = method_getName(mlist?.pointee).description
            let num = method_getNumberOfArguments(mlist?.pointee)
            var type: MemberType
            var start: String.Index
            var end: String.Index
            if name.hasPrefix(methodPrefix) && num >= 3 {
                type = MemberType.method
                start = name.characters.index(name.startIndex, offsetBy: 7)
                end = name.characters.index(after: start)
                while name[end] != Character(":") {
                    end = name.characters.index(after: end)
                }
            } else if name.hasPrefix(getterPrefix) && num == 2 {
                type = MemberType.getter
                start = name.characters.index(name.startIndex, offsetBy: 7)
                end = name.endIndex
            } else if name.hasPrefix(setterPrefix) && num == 3 {
                type = MemberType.setter
                start = name.characters.index(name.startIndex, offsetBy: 10)
                end = name.characters.index(before: name.endIndex)
            } else if name.hasPrefix(ctorPrefix) {
                type = MemberType.constructor
                start = name.startIndex
                end = name.characters.index(start, offsetBy: 4)
            } else {
                mlist = mlist?.successor()
                continue
            }
            if !callback(name[start..<end], type, (mlist?.pointee!)!, cls) {
                free(methodList)
                return false
            }
            mlist = mlist?.successor()
        }
        free(methodList)
        return true
    }
}
