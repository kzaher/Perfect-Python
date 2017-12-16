//
//  PerfectPython.swift
//  Perfect-Python
//
//  Created by Rockford Wei on 2017-08-18.
//  Copyright © 2017 PerfectlySoft. All rights reserved.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2017 - 2018 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import Python3
import struct Foundation.Decimal

extension String {
    var wchars: [wchar_t] {
        return self.flatMap { $0.unicodeScalars }.map { Int32($0.value) } + [0]
    }
}

/// public protocol for convertion between Python and Swift tyeps
/// suggested by Chris Lattner, Nov 3rd, 2017
public protocol Pythonable {

    /// convert a PyObj to a Swift object, will return nil if failed
    init(python : PyObj) throws

    /// convert a Swift obj to a Python object, will return nil if faied
    func python() throws -> PyObj
}

extension String: Pythonable {

    /// convert string to PyObj
    public func python() throws -> PyObj {
        if let ref = PyUnicode_FromString(self) {
            return PyObj(ref)
        }
        else {
            throw PyObj.Exception.InvalidType
        }
    }

    /// convert PyObj to string
    public init(python: PyObj) throws {
        guard let p = PyUnicode_AsUTF8(python.ref), let s = String(validatingUTF8: p) else {
            throw PyObj.Exception.InvalidType
        }
        self = s
    }
}

extension Int: Pythonable {

    /// convert integer to PyObj
    public func python() throws -> PyObj {
        if let ref = PyLong_FromLong(self) {
            return PyObj(ref)
        }
        else {
            throw PyObj.Exception.InvalidType
        }
    }

    /// convert PyObj to integer
    public init(python: PyObj) throws {
        self = PyLong_AsLong(python.ref)
    }
}

extension Double: Pythonable {

    /// convert Double to PyObj
    public func python() throws -> PyObj {
        if let ref = PyFloat_FromDouble(self) {
            return PyObj(ref)
        }
        else {
            throw PyObj.Exception.InvalidType
        }
    }
    /// convert PyObj to Double
    public init(python: PyObj) throws {
        self = PyFloat_AsDouble(python.ref)
    }
}

extension Decimal: Pythonable {
    /// convert Double to PyObj
    public func python() throws -> PyObj {
        return try Python.System._decimal.construct(try self.description.python()).unwrapOrThrow()
    }
    /// convert PyObj to Double
    public init(python: PyObj) throws {
        self = try Decimal(string: try python.call(String.self, "__str__").unwrapOrThrow()).unwrapOrThrow()
    }
}

extension UnsafeMutablePointer where Pointee == FILE {
    public func python() throws -> PyObj {
        return try PythonBridgeableFILE(file: fileno(self), path: "", mode: "rw").python()
    }
}

public struct PythonBridgableDictionary<Key: Hashable & Pythonable, Value: Pythonable> {
    public var dictionary: [Key: Value]

    public init(dictionary: [Key: Value]) {
        self.dictionary = dictionary
    }
}

extension PythonBridgableDictionary: Pythonable {
    /// convert a PyObj to a Swift object, will return nil if failed
    public init(python : PyObj) throws {
        var dict: [Key: Value] = [:]
        if let keys = PyDict_Keys(python.ref) {
            for i in 0 ..< PyDict_Size(python.ref) {
                if let key = PyList_GetItem(keys, i),
                    let value = PyDict_GetItem(python.ref, key) {
                    Py_IncRef(key)
                    Py_IncRef(value)

                    dict[try Key(python: PyObj(key))] = try Value(python: PyObj(value))
                }
            }
            defer {
                Py_DecRef(keys)
            }
        }
        else {
            throw PyObj.Exception.InvalidType
        }


        self.dictionary = dict
    }

    /// convert a Swift obj to a Python object, will return nil if faied
    public func python() throws -> PyObj {
        let ref = PyDict_New()!
        for (i, j) in self.dictionary {
            let iPy = try i.python()
            let jPy = try j.python()
            Py_IncRef(iPy.ref)
            Py_IncRef(jPy.ref)
            _ = PyDict_SetItem(ref, iPy.ref, jPy.ref)
        }
        return PyObj(ref)
    }
}

public extension Dictionary where Key: Pythonable, Value: Pythonable {
    public var python: PythonBridgableDictionary<Key, Value> {
        return PythonBridgableDictionary(dictionary: self)
    }
}

public struct PythonBridgableArray<Element: Pythonable> {
    public var array: [Element]

    public init(array: [Element]) {
        self.array = array
    }
}

extension PythonBridgableArray: Pythonable {
    public init(python : PyObj) throws {
        self.array = try (0 ..< PyList_Size(python.ref)).flatMap { i -> [Element] in
            if let element = PyList_GetItem(python.ref, i) {
                Py_IncRef(element)
                return [try Element(python: PyObj(element))]
            }
            return []
        }
    }

    public func python() throws -> PyObj {
        let list = PyList_New(self.array.count)!
        for i in 0 ..< self.array.count {
            let j = try self.array[i].python()
            Py_IncRef(j.ref)
            _ = PyList_SetItem(list, i, j.ref)
        }
        return PyObj(list)
    }
}

extension Array where Element: Pythonable {
    public var python: PythonBridgableArray<Element> {
        return PythonBridgableArray(array: self)
    }
}

extension Array where Element == Pythonable {
    public func pythonTuple() throws -> PyObj {
        guard self.count > 0,
            let args = PyTuple_New(self.count) else {
                throw PyObj.Exception.NullArray
        }
        for i in 0 ..< self.count {
            let obj = try self[i].python()
            Py_IncRef(obj.ref)
            guard PyTuple_SetItem(args, i, obj.ref) == 0 else {
                throw PyObj.Exception.ElementInsertionFailure
            }
        }
        return PyObj(args)
    }
}

public struct PythonBridgeableFILE {
    public let file: Int32
    public let path: String
    public let mode: String

    public init(file: Int32, path: String, mode: String) {
        self.file = file
        self.path = path
        self.mode = mode
    }
}

extension PythonBridgeableFILE: Pythonable {
    public init(python: PyObj) throws {
        throw PyObj.Exception.InvalidType
    }

    public func python() throws -> PyObj {
        return PyObj(PyFile_FromFd(
            file,
            UnsafeMutablePointer<Int8>(mutating: path),
            UnsafeMutablePointer<Int8>(mutating: mode),
            -1,
            nil,
            nil,
            nil,
            1))
    }
}

/// Swift Wrapper Class of UnsafeMutablePointer<PyObject>
final public class PyObj {

    /// reference pointer
    public let ref: UnsafeMutablePointer<PyObject>

    /// Errors
    public enum Exception: Error {

        /// Unsupported Python Type
        case InvalidType

        /// The array is unexpectedly null.
        case NullArray

        /// element can not be inserted
        case ElementInsertionFailure

        /// unable to convert into a string
        case InvalidString

        /// python throws
        case Throw(String)
    }

    /// Load a python module from the given path and turn the module into a PyObj
    /// - parameters:
    ///   - path: String, the module directory
    ///   - import: String, the module name without path and suffix
    /// - throws: `Exception.ImportFailure`
    public init(path: String? = nil, `import`: String) throws {
        ref = try Python.inWorkingDirectory(path: path) {
                if let reference = PyImport_ImportModule(`import`) {
                    return reference
                } else {
                    throw Exception.Throw(Python.LastError)
                }
        }
    }

    public init(systemPath: String) throws {
        self.ref = PySys_GetObject(systemPath)
        Py_IncRef(ref)
    }

    /// Initialize a PyObj by its reference pointer
    /// - parameters:
    ///   - reference: UnsafeMutablePointer<PyObject>, the reference pointer
    public init(_ reference: UnsafeMutablePointer<PyObject>) {
        ref = reference
    }

    /// get the type name
    public var `type`: String {
        return String(cString: ref.pointee.ob_type.pointee.tp_name)
    }

    /// call a function by its name and the given arguments, if the PyObj itself
    /// is a module or a class instance.
    /// - parameters:
    ///   - functionName: String, name of the function to call
    ///   - args: [Any]?, the arguement array.
    /// - returns: PyObj?
    public func call<T: Pythonable>(_ returnType: T.Type = T.self, _ functionName: String, args: [Pythonable] = []) throws -> T? {
        guard let function = PyObject_GetAttrString(ref, functionName)
            else {
                return nil
        }
        defer {
            Py_DecRef(function)
        }
        let result: UnsafeMutablePointer<PyObject>?
        if args.isEmpty {
            result = PyObject_CallObject(function, nil)
        } else {
            result = PyObject_CallObject(function, try args.pythonTuple().ref)
        }
        guard let r = result else {
            throw Exception.Throw(Python.LastError)
        }
        return try T(python: PyObj(r))
    }

    public func call<T: Pythonable>(_ returnType: T.Type = T.self, _ functionName: String, _ args: Pythonable ...) throws -> T? {
        return try self.call(returnType, functionName, args: args)
    }

    /// initialize the current python object to a class instance.
    /// for example, suppose there is a class called "Person" and can be
    /// initialized with two properties: name and age. then
    /// ```
    /// let personClass = try PyObj(path:, import:)
    /// ```
    /// can get the class, and
    /// ```
    /// let person = personClass?.construct(["rocky", 24])
    /// ```
    /// will get the object instance.
    /// - parameters:
    ///   - arguements: [Any]?, optional parameters to initialize the instance.
    /// - returns: PyObj?
    public func construct(_ arguments: [Pythonable] = []) throws -> PyObj? {
        if let obj = PyObject_CallObject(ref, try arguments.pythonTuple().ref) {
            return PyObj(obj)
        } else {
            return nil
        }
    }

    public func construct(_ arguments: Pythonable ...) throws -> PyObj? {
        return try construct(arguments)
    }

    /// load a variable by its name.
    /// - parameters:
    ///   - variableName: String, name of the variable to load
    /// - returns: PyObj?
    public func load<T: Pythonable>(_ type: T.Type, _ variableName: String) throws -> T? {
        if let reference = PyObject_GetAttrString(ref, variableName) {
            return try T(python: PyObj(reference))
        } else {
            return nil
        }
    }

    public func load(_ variableName: String) throws -> PyObj? {
        return try self.load(PyObj.self, variableName)
    }

    var moduleDictionary: PyObj {
        return PyObj(PyModule_GetDict(ref))
    }

    subscript(mappingIndex: String) -> PyObj? {
        get {
            if let obj = PyMapping_GetItemString(ref, mappingIndex) {
                return PyObj(obj)
            } else {
                return nil
            }
        }
        set {
            guard PyMapping_SetItemString(ref, mappingIndex, newValue?.ref) == 0 else {
                fatalError("Mapping not set")
            }
        }
    }

    /// save a variable with a new value and by its name
    /// - parameters:
    ///   - variableName: String, name of the variable to save
    ///   - newValue: new value to save
    /// - throws: `Exception.ValueSavingFailure`
    public func save(_ variableName: String, newValue: Pythonable) throws {
        guard 0 == PyObject_SetAttrString(ref, variableName, try newValue.python().ref) else {
            throw Exception.Throw(Python.LastError)
        }
    }

    deinit {
        Py_DecRef(ref)
    }

    /// get version info
    public static var Version: String? {
        return Python.System._version
    }

    public func `as`<T: Pythonable>(_ type: T.Type = T.self) -> T? {
        return try? T(python: self)
    }
}

extension PyObj: Pythonable {
    /// convert a PyObj to a Swift object, will return nil if failed
    public convenience init(python : PyObj) throws {
        Py_IncRef(python.ref)
        self.init(python.ref)
    }

    /// convert a Swift obj to a Python object, will return nil if faied
    public func python() throws -> PyObj {
        return self
    }
}

extension PyObj: CustomStringConvertible {
    public var description: String {
        return (try? self.call(String.self, "__str__")).flatMap { $0 } ?? "Error converting to Swift"
    }
}

public class Python {

    public static func inWorkingDirectory<T>(path: String?, action: () throws -> T) rethrows -> T {

        if let path = path {
            let previousPaths = try! PyObj(systemPath: "path")

            let adjustedPaths = try! Python.System._deepCopy.call(PyObj.self, "deepcopy", previousPaths).unwrapOrThrow()

            _ = try! adjustedPaths.call(PyObj.self, "append", path)

            defer {
                PySys_SetObject("path", previousPaths.ref)
            }

            PySys_SetObject("path", adjustedPaths.ref)
            return try action()
        }
        else {
            return try action()
        }
    }

    static var _syslib: Python? = nil

    public static let System: Python = Python()

    let _version: String
    let _sys: PyObj
    let _decimal: PyObj
    let _deepCopy: PyObj

    public static var LastError: String {
        PyErr_PrintEx(1)

        let type = (try? System._sys["last_type"]?.load(String.self, "__name__")).flatMap { $0 } ?? "<no type>"
        let value = System._sys["last_value"]?.description ?? "<no value>"
        let traceback = System._sys["last_traceback"]?.description ?? "<no traceback>"

        return type + ": " + value + "\n"
            + traceback
    }

    public init() {
        Py_Initialize()
        let sys = try! PyObj(import: "sys").moduleDictionary
        let version = try! String(python: sys["version"]!)

        //print(try! PythonBridgableArray<String>(python: try! PyObj(systemPath: "path")).array)

        let decimal = try! PyObj(import: "decimal").load("Decimal")!
        let deepcopy = try! PyObj(import: "copy")

        _sys = sys
        _version = version
        _decimal = decimal
        _deepCopy = deepcopy
    }
}


fileprivate struct SystemError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    let file: String
    let line: UInt
    let function: String
    let message: String

    public init(message: String = "", file: String = #file, line: UInt = #line, function: String = #function) {
        self.file = file
        self.line = line
        self.function = function
        self.message = message
    }
}

extension SystemError {
    public var description: String {
        return "'\(self.message)' [\(file):\(line)] @ \(function)"
    }

    public var debugDescription: String {
        return description
    }
}

extension Optional {
    fileprivate func unwrapOrThrow(message: String = "", file: String = #file, line: UInt = #line, function: String = #function) throws -> Wrapped {
        guard let value = self else {
            throw SystemError(message: message, file: file, line: line, function: function)
        }
        return value
    }
}

