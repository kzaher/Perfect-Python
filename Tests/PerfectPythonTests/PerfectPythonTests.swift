//
//  PerfectPythonTests.swift
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
import XCTest
@testable import Python3
@testable import PerfectPython

class PerfectPythonTests: XCTestCase {

    static var allTests = [
        ("testLastError", testLastError),
        ("testCallback", testCallback),
        ("testExample", testExample),
        ("testVersion", testVersion),
        ("testBasic", testBasic),
        ("testBasic2", testBasic2),
        ("testClass", testClass),
        ("testClass2", testClass2)
    ]

    func writeScript(path: String, content: String) {
        guard let f = fopen(path, "w") else {
            XCTFail("\(path) is invalid")
            return
        }
        _ = content.withCString { pstring in
            fwrite(pstring, 1, content.count, f)
        }
        fclose(f)
    }

    override func setUp() {
        Py_Initialize()
        var program = "class Person:\n\tdef __init__(self, name, age):\n\t\tself.name = name\n\t\tself.age = age\n\tdef intro(self):\n\t\treturn 'Name: ' + self.name + ', Age: ' + str(self.age)\n"
        var path = "/tmp/clstest.py"
        writeScript(path: path, content: program)
        program = "def mymul(num1, num2):\n\treturn num1 * num2;\n\ndef mydouble(num):\n\treturn num * 2;\n\nstringVar = 'Hello, world'\nlistVar = ['rocky', 505, 2.23, 'wei', 70.2]\ndictVar = {'Name': 'Rocky', 'Age': 17, 'Class': 'Top'};\n"
        path = "/tmp/helloworld.py"
        writeScript(path: path, content: program)
    }

    override func tearDown() {
        //Py_Finalize()
        unlink("/tmp/clstest.py")
        unlink("/tmp/clstest.pyc")
        unlink("/tmp/helloworld.py")
        unlink("/tmp/helloworld.pyc")
    }

    func testExample() {
        let p = PyObject()
        print(p)
    }

    func testLastError() {
        for _ in 0 ..< 10 {
                do {
                    let _ = try PyObj(path: "/nowhere", import: "inexisting")
                    XCTFail()
                } catch PyObj.Exception.Throw(let msg) {
                    XCTAssertEqual(msg, "ModuleNotFoundError: No module named 'inexisting'\nNone")
                } catch {
                    XCTFail(error.localizedDescription)
                }
        }
    }

    func testVersion() {
        if let v = PyObj.Version {
            XCTAssertTrue(v.hasPrefix("3.6"))
        } else {
            XCTFail("version checking failed")
        }
    }

    func testClass2() {
        do {
            let pymod = try PyObj(path: "/tmp", import: "clstest")
            for _ in 0 ..< 10 {
                if let personClass = try pymod.load("Person"),
                    let person = try personClass.construct("rocky", 24),
                    let name = try person.load(String.self, "name"),
                    let age = try person.load(Int.self, "age") {
                    print("loaded with: ", name, age)
                    let intro = try person.call(String.self, "intro") ?? "missing"
                    XCTAssertEqual(name, "rocky")
                    XCTAssertEqual(age, 24)
                    XCTAssertNotEqual(intro, "missing")
                }
            }
        }catch {
            XCTFail("\(error)")
        }
    }

    func testClass() {
        Python.inWorkingDirectory(path: "/tmp") {
            let module = PyImport_ImportModule("clstest")!

            for _ in 0 ..< 100 {
                if
                    let personClass = PyObject_GetAttrString(module, "Person"),
                    let args = PyTuple_New(2),
                    let name = PyUnicode_FromString("Rocky"),
                    let age = PyLong_FromLong(24),
                    PyTuple_SetItem(args, 0, name) == 0,
                    PyTuple_SetItem(args, 1, age) == 0,
                    let personObj = PyObject_CallObject(personClass, args),
                    let introFunc = PyObject_GetAttrString(personObj, "intro"),
                    let introRes = PyObject_CallObject(introFunc, nil),
                    let intro = PyUnicode_AsUTF8(introRes)
                {
                    print(String(cString: intro))
                    Py_DecRef(introFunc)
                    Py_DecRef(introRes)
                    Py_DecRef(args)
                    //Py_DecRef(name)
                    //Py_DecRef(age)
                    Py_DecRef(personObj)
                } else {
                    XCTFail("class variable failed")
                }
            }
            Py_DecRef(module)
        }
    }

    func testBasic2() {
        let program = "def mymul(num1, num2):\n\treturn num1 * num2;\n\nstringVar = 'Hello, world'\nlistVar = ['rocky', 505, 2.23, 'wei', 70.2]\ndictVar = {'Name': 'Rocky', 'Age': 17, 'Class': 'Top'};\n"
        let path = "/tmp/hola.py"
        writeScript(path: path, content: program)
        do {
            let pymod = try PyObj(path: "/tmp", import: "hola")
            if let ires = try pymod.call(Int.self, "mymul", args: [2, 3]) {
                XCTAssertEqual(ires, 6)
            } else {
                XCTFail("function call failure")
            }
            let testString = "Hola, 🇨🇳🇨🇦"
            if let str = try pymod.load(String.self, "stringVar") {
                do {
                    XCTAssertEqual(str, "Hello, world")
                    try pymod.save("stringVar", newValue: testString)
                }catch{
                    XCTFail(error.localizedDescription)
                }
            } else {
                XCTFail("string call failure")
            }
            if let str2 = try pymod.load(String.self, "stringVar") {
                XCTAssertEqual(str2, testString)
            } else {
                XCTFail("string call failure")
            }
            if let list = try pymod.load(PythonBridgableArray<PyObj>.self, "listVar")?.array {
                XCTAssertEqual(list.count, 5)
                print(list)
            } else {
                XCTFail("loading list failure")
            }
            if let dict = try pymod.load(PythonBridgableDictionary<String, PyObj>.self, "dictVar")?.dictionary {
                XCTAssertEqual(dict.count, 3)
                print(dict)
            }
        }catch {
            XCTFail(error.localizedDescription)
        }

    }

    func testBasic() {
        Python.inWorkingDirectory(path: "/tmp") {
            if let module = PyImport_ImportModule("helloworld"),
                let function = PyObject_GetAttrString(module, "mydouble"),
                let num = PyLong_FromLong(2),
                let args = PyTuple_New(1),
                PyTuple_SetItem(args, 0, num) == 0,
                let res = PyObject_CallObject(function, args) {
                let four = PyLong_AsLong(res)
                XCTAssertEqual(four, 4)
                if let strObj = PyObject_GetAttrString(module, "stringVar"),
                    let pstr = PyUnicode_AsUTF8(strObj) {
                    let strvar = String(cString: pstr)
                    print(strvar)
                    Py_DecRef(function)
                    Py_DecRef(args)
                    Py_DecRef(num)
                    Py_DecRef(res)
                    Py_DecRef(strObj)
                } else {
                    XCTFail("string variable failed")
                }
                if let listObj = PyObject_GetAttrString(module, "listVar") {
                    XCTAssertEqual(String(cString: listObj.pointee.ob_type.pointee.tp_name), "list")
                    let size = PyList_Size(listObj)
                    XCTAssertEqual(size, 5)
                    for i in 0 ..< size {
                        if let item = PyList_GetItem(listObj, i) {
                            let j = item.pointee
                            let tpName = String(cString: j.ob_type.pointee.tp_name)
                            let v: Any?
                            switch tpName {
                            case "str":
                                v = String(cString: PyUnicode_AsUTF8(item))
                                break
                            case "int":
                                v = PyLong_AsLong(item)
                            case "float":
                                v = PyFloat_AsDouble(item)
                            default:
                                v = nil
                            }
                            if let v = v {
                                print(i, tpName, v)
                            } else {
                                print(i, tpName, "Unknown")
                            }
                            Py_DecRef(item)
                        }
                    }
                    Py_DecRef(listObj)
                } else {
                    XCTFail("list variable failed")
                }

                if let dicObj = PyObject_GetAttrString(module, "dictVar"),
                    let keys = PyDict_Keys(dicObj) {
                    XCTAssertEqual(String(cString: dicObj.pointee.ob_type.pointee.tp_name), "dict")
                    let size = PyDict_Size(dicObj)
                    XCTAssertEqual(size, 3)
                    for i in 0 ..< size {
                        guard let key = PyList_GetItem(keys, i),
                            let item = PyDict_GetItem(dicObj, key) else {
                                continue
                        }
                        let keyName = String(cString: PyUnicode_AsUTF8(key))
                        let j = item.pointee
                        let tpName = String(cString: j.ob_type.pointee.tp_name)
                        let v: Any?
                        switch tpName {
                        case "str":
                            v = String(cString: PyUnicode_AsUTF8(item))
                            break
                        case "int":
                            v = PyLong_AsLong(item)
                        case "float":
                            v = PyFloat_AsDouble(item)
                        default:
                            v = nil
                        }
                        if let v = v {
                            print(keyName, tpName, v)
                        } else {
                            print(keyName, tpName, "Unknown")
                        }
                        Py_DecRef(item)
                    }
                    Py_DecRef(keys)
                    Py_DecRef(dicObj)
                } else {
                    XCTFail("dictionary variable failed")
                }
                Py_DecRef(module)
            } else {
                XCTFail("library import failed")
            }
        }
    }

    func testCallback() {
        let program = "def callback(msg):\n\treturn 'callback: ' + msg\ndef caller(info, func):\n\treturn func(info)"
        let path = "/tmp/callback.py"
        writeScript(path: path, content: program)
        do {
            let pymod = try PyObj(path: "/tmp", import: "callback")
            if let funSource = try pymod.load(PyObj.self, "callback") {
                if let result = try pymod.call(String.self, "caller", "Hello", funSource) {
                    XCTAssertEqual(result, "callback: Hello")
                    //print("callback result:", result)
                } else {
                    XCTFail("callback failure")
                }
            } else {
                XCTFail("callback not found")
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testDecimal() {
        for _ in 0 ..< 10 {
                //let program = "from decimal import Decimal\n\ndef a(input):\n\treturn input + Decimal(1.0)\n"
                let program = "from decimal import Decimal\n\ndef a(input):\n\treturn input + Decimal(1.0)\n"
                let path = "/tmp/decimaltest.py"
                writeScript(path: path, content: program)
                do {
                    let pymod = try PyObj(path: "/tmp", import: "decimaltest")
                    if let result = try pymod.call(Decimal.self, "a", Decimal(2.0)) {
                        XCTAssertEqual(result, Decimal(3.0))
                        //print("callback result:", result)
                    } else {
                        XCTFail("callback failure")
                    }
                } catch {
                    XCTFail(error.localizedDescription)
                }
        }
    }
}
