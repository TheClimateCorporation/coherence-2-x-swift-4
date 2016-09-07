//
//  WADLMethod.swift
//  Pods
//
//  Created by Tony Stone on 8/27/16.
//
//

import Swift

/**
    WADL Response Element
 
    - Seealso:
 
        [Web Application Description Language, 2.8 Method](https://www.w3.org/Submission/wadl/#x3-90002.8)
 */
class WADLMethod : WADLElement  {
    
    init(name: String, id: String?, parent: WADLElement?) {
        self.name = name
        self.id   = id
        self.href = nil
        self.parent = parent
    }
    init(href: URL, parent: WADLElement?) {
        self.href = href
        self.id   = nil
        self.name = nil
        self.parent = parent
    }
    
    // Attributes
    let href: URL?
    let name: String?
    let id: String?
    
    var otherAttributes: [String : String]      = [:]
    
    // Elements
    var docs: [WADLDoc]                         = []
    var request: WADLRequest?                   = nil
    var responses: [WADLResponse]               = []
    
    var otherElements: [XMLElement]             = []
    
    weak var parent: WADLElement?
}
