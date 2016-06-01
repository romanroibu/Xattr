//
//  Xattr.swift
//  Xattr
//
//  Created by Roman Roibu on 27/05/16.
//
//

import Foundation

public typealias Data = NSData
public typealias Number = NSNumber

//MARK:- ValueWrapper

/// Protocol for types that manage attribute serialization
public protocol ValueWrapper {
    associatedtype ValueType

    /// Deserialization
    static func xattrValueFrom(data data: Data) -> ValueType?

    /// Serialization
    static func xattrDataFrom(value value: ValueType) -> Data?
}

//MARK:- Data ValueWrapper

extension Data: ValueWrapper {
    public static func xattrValueFrom(data data: Data) -> Data? {
        return data
    }
    public static func xattrDataFrom(value value: Data) -> Data? {
        return value
    }
}

//MARK:- Numerical ValueWrapper

/// Protocol for numerical types in Swift's type system
public protocol NumericalValueWrapper: ValueWrapper {}

extension NumericalValueWrapper {
    private typealias TypedUnsafeMutablePointer = UnsafeMutablePointer<Self>
    private typealias TypedUnsafePointer = UnsafePointer<Self>

    public static func xattrValueFrom(data data: Data) -> Self? {
        let rawMemory = data.bytes

        //Empty data
        guard rawMemory != nil else { return nil }

        //Return the extracted number as Self
        return TypedUnsafePointer(rawMemory).memory
    }

    public static func xattrDataFrom(value value: Self) -> Data? {
        let size = sizeof(self)
        let rawMemory = UnsafeMutablePointer<Void>.alloc(size)

        //Failed to allocate memory
        guard rawMemory != nil else { return nil }

        //Store the point count in the first portion of the buffer
        TypedUnsafeMutablePointer(rawMemory).memory = value

        //Tell Data not to bother copying memory.
        //For consistency and since we can't guarantee the memory allocated
        //by UnsafeMutablePointer can just be freed,
        //Provide a deallocator block.
        return Data(bytesNoCopy: rawMemory, length: size) { (ptr, length) in
            ptr.destroy(length)
            ptr.dealloc(length)
        }
    }
}

//Signed Integer Types

extension Int:   NumericalValueWrapper {}
extension Int8:  NumericalValueWrapper {}
extension Int16: NumericalValueWrapper {}
extension Int32: NumericalValueWrapper {}
extension Int64: NumericalValueWrapper {}

//Unsigned Integer Types

extension UInt:   NumericalValueWrapper {}
extension UInt8:  NumericalValueWrapper {}
extension UInt16: NumericalValueWrapper {}
extension UInt32: NumericalValueWrapper {}
extension UInt64: NumericalValueWrapper {}

//Floating Point Types

extension Float: NumericalValueWrapper {}
extension Double: NumericalValueWrapper {}

//MARK: String ValueWrapper

/// Protocol for types that serialize/deserialize attribute values to String, with a specific encoding
public protocol StringValueWrapper: ValueWrapper {
    static var xattrValueEncoding: NSStringEncoding { get }
}

extension StringValueWrapper {
    public static func xattrValueFrom(data data: Data) -> String? {
        return NSString(data: data, encoding: self.xattrValueEncoding) as? String
    }
    public static func xattrDataFrom(value value: String) -> Data? {
        return (value as NSString).dataUsingEncoding(self.xattrValueEncoding)
    }
}

//String Encoding Types

public typealias UTF8String = String

public struct UTF16String {}
public struct UTF16LittleEndianString {}
public struct UTF16BigEndianString {}

public struct UTF32String {}
public struct UTF32LittleEndianString {}
public struct UTF32BigEndianString {}

extension UTF8String: StringValueWrapper {
    public static let xattrValueEncoding = NSUTF8StringEncoding
}
extension UTF16String: StringValueWrapper {
    public static let xattrValueEncoding = NSUTF16StringEncoding
}
extension UTF16LittleEndianString: StringValueWrapper {
    public static let xattrValueEncoding = NSUTF16LittleEndianStringEncoding
}
extension UTF16BigEndianString: StringValueWrapper {
    public static let xattrValueEncoding = NSUTF16BigEndianStringEncoding
}
extension UTF32String: StringValueWrapper {
    public static let xattrValueEncoding = NSUTF32StringEncoding
}
extension UTF32LittleEndianString: ValueWrapper, StringValueWrapper {
    public static let xattrValueEncoding = NSUTF32LittleEndianStringEncoding
}
extension UTF32BigEndianString: StringValueWrapper {
    public static let xattrValueEncoding = NSUTF32BigEndianStringEncoding
}

//TODO: Add all the other string encoding wrappers

//MARK:- Xattr

public struct Xattr<T: ValueWrapper> {

//MARK:- Get

    //TODO: Document parameters and return value
    /// - Throws: `Xattr.Error`
    ///     - **`NoAttribute`**     if the extended attribute does not exist
    ///     - **`NotSupported`**    if the file system does not support extended attributes or has the feature disabled
    ///     - **`Range`**           if the value (as indicated by size) is too small to hold the extended attribute data
    ///     - **`Permission`**      if the `name`d attribute is not permitted for this type of object
    ///     - **`Invalid`**         if `name` is invalid or `options` has an unsupported bit set
    ///     - **`IsDirectory`**     if `path` or `fd` do not refer to a regular file and the attribute in question is only applicable to files (similar to `.Permission`)
    ///     - **`NotDirectory`**    if a component of `path`'s prefix is not a directory
    ///     - **`NameTooLong`**     if `name` exceeds `Limits.MaxNameLength` UTF-8 bytes, or a component of `path` exceeds `Limits.MaxPathComponentLength` characters, or the entire `path` exceeds `Limits.MaxPathComponentLength` characters
    ///     - **`Acces`**           if search permission is denied for a component of `path` or the attribute is not allowed to be read (e.g. an ACL prohibits reading the attributes of this file)
    ///     - **`Loop`**            if too many symbolic links were encountered in translating the `path` name
    ///     - **`Fault`**           if `path` or `name` points to an invalid address
    ///     - **`IO`**              if an I/O error occurred while reading from or writing to the file system
    public static func get(key: String, path: String, options: Options=[]) throws -> T.ValueType? {
        return try self.get(key, reference: .Path(path), options: options)
    }

    //TODO: Add doc
    public static func get(key: String, fd: Int32, options: Options=[]) throws -> T.ValueType? {
        return try self.get(key, reference: .FileDescriptor(fd), options: options)
    }

    private static func get(key: String, reference: FileReference, options opts: Options) throws -> T.ValueType? {
        let options = opts.getxattr.rawValue

        let length = self._getxattr(reference, name: key, value: nil, size: 0, position: 0, options: options)
        guard length != -1 else {
            //There was an error, throw it
            throw Error(errno: errno)
        }

        guard length > 0 else {
            //The value is of length 0, return nil
            return nil
        }

        let bytes = UnsafeMutablePointer<Void>.alloc(length)
        guard bytes != nil else {
            //Failed to allocate memory
            return nil
        }

        guard self._getxattr(reference, name: key, value: bytes, size: length, position: 0, options: options) != -1 else {
            //There was an error, throw it
            throw Error(errno: errno)
        }

        let data  = Data(bytes: bytes, length: length)
        let value = T.xattrValueFrom(data: data)

        return value
    }

//MARK:- Set

    //TODO: Document parameters and return value
    /// - Throws: `Xattr.Error`
    ///     - **`Exist`**               if `options` contains `Option.Create` and the `name`d attribute already exists
    ///     - **`NoAttribute`**         if `options` is set to`Option.Replace` and the `name`d attribute does not exist
    ///     - **`NotSupported`**        if the file system does not support extended attributes or has them disabled
    ///     - **`ReadOnlyFileSystem`**  if the file system is mounted read-only
    ///     - **`Range`**               if the data size of the attribute is out of range (some attributes have size restrictions)
    ///     - **`Permission`**          if attributes cannot be associated with this type of object (e.g. attributes are not allowed for resource forks)
    ///     - **`Invalid`**             if `name` or `options` is invalid (`name` must be valid UTF-8 and `options` must make sense)
    ///     - **`NotDirectory`**        if a component of `path` is not a directory
    ///     - **`NameTooLong`**         if `name` exceeds `Limits.MaxNameLength` UTF-8 bytes, or a component of `path` exceeds `Limits.MaxPathComponentLength` characters, or the entire `path` exceeds `Limits.MaxPathComponentLength` characters
    ///     - **`Acces`**               if search permission is denied for a component of `path` or permission to set the attribute is denied
    ///     - **`Loop`**                if too many symbolic links were encountered resolving path.
    ///     - **`Fault`**               if `path` or `name` points to an invalid address
    ///     - **`IO`**                  if an I/O error occurred while reading from or writing to the file system
    ///     - **`TooBig`**              if the data size of the extended attribute is too large
    ///     - **`NoSpace`**             if there is not enough space left on the file system
    public static func set(key: String, value: T.ValueType, path: String, options: Options=[]) throws {
        try self.set(key, value: value, reference: .Path(path), options: options)
    }

    //TODO: Add doc
    public static func set(key: String, value: T.ValueType, fd: Int32, options: Options=[]) throws {
        try self.set(key, value: value, reference: .FileDescriptor(fd), options: options)
    }

    private static func set(key: String, value: T.ValueType, reference: FileReference, options opts: Options) throws {
        let options = opts.setxattr.rawValue

        guard let data = T.xattrDataFrom(value: value) else {
            //Failed to deserialize
            return
        }

        guard self._setxattr(reference, name: key, value: data.bytes, size: data.length, position: 0, options: options) != -1 else {
            //There was an error, throw it
            throw Error(errno: errno)
        }
    }

//MARK:- Remove

    //TODO: Document parameters and return value
    /// - Throws: `Xattr.Error`
    ///     - **`NoAttribute`**         if the specified extended attribute does not exist
    ///     - **`NotSupported`**        if the file system does not support extended attributes or has the feature disabled
    ///     - **`ReadOnlyFileSystem`**  if the file system is mounted read-only
    ///     - **`Permission`**          if this type of object does not support extended attributes
    ///     - **`Invalid`**             if `name` or `options` is invalid (`name` must be valid UTF-8 and `options` must make sense)
    ///     - **`NotDirectory`**        if a component of the `path`'s prefix is not a directory
    ///     - **`NameTooLong`**         if `name` exceeds `Limits.MaxNameLength` UTF-8 bytes, or a component of `path` exceeds `Limits.MaxPathComponentLength` characters, or the entire `path` exceeds `Limits.MaxPathComponentLength` characters
    ///     - **`Acces`**               if search permission is denied for a component `path` or permission to remove the attribute is denied
    ///     - **`Loop`**                if too many symbolic links were encountered in `path`
    ///     - **`Fault`**               if `path` or `name` points to an invalid address
    ///     - **`IO`**                  if an I/O error occurred while reading from or writing to the file system
    public static func remove(key: String, path: String, options: Options=[]) throws {
        try self.remove(key, reference: .Path(path), options: options)
    }

    //TODO: Add doc
    public static func remove(key: String, fd: Int32, options: Options=[]) throws {
        try self.remove(key, reference: .FileDescriptor(fd), options: options)
    }

    private static func remove(key: String, reference: FileReference, options opts: Options) throws {
        let options = opts.removexattr.rawValue

        guard self._removexattr(reference, name: key, options: options) != -1 else {
            //There was an error, throw it
            throw Error(errno: errno)
        }
    }

//MARK:- Keys

    //TODO: Document parameters and return value
    /// - Throws: `Xattr.Error`
    ///     - **`NotSupported`**    if the file system does not support extended attributes or has the feature disabled
    ///     - **`Range`**           if `namebuf` (as indicated by size) is too small to hold the list of names
    ///     - **`Permission`**      if `path` or `fd` refer to a file system object that does not support extended attributes (e.g. resource forks don't support extended attributes)
    ///     - **`NotDirectory`**    if a component of `path`'s prefix is not a directory
    ///     - **`NameTooLong`**     if `name` exceeds `Limits.MaxNameLength` UTF-8 bytes, or a component of `path` exceeds `Limits.MaxPathComponentLength` characters, or the entire `path` exceeds `Limits.MaxPathComponentLength` characters
    ///     - **`Acces`**           is search permission is denied for a component of `path` or permission is denied to read the list of attributes from this file
    ///     - **`Loop`**            if too many symbolic links were encountered resolving `path`
    ///     - **`Fault`**           if `path` points to an invalid address
    ///     - **`IO`**              if an I/O error occurred
    ///     - **`Invalid`**         if `options` does not make sense
    public static func keys(path path: String, options: Options=[]) throws -> [String] {
        return try self.keys(reference: .Path(path), options: options)
    }

    //TODO: Add doc
    public static func key(fd fd: Int32, options: Options=[]) throws -> [String] {
        return try self.keys(reference: .FileDescriptor(fd), options: options)
    }

    private static func keys(reference reference: FileReference, options opts: Options) throws -> [String] {
        let options = opts.listxattr.rawValue

        let length = self._listxattr(reference, namebuff: nil, size: 0, options: options)
        guard length != -1 else {
            //There was an error, throw it
            throw Error(errno: errno)
        }

        let bytes = UnsafeMutablePointer<Int8>.alloc(length)
        guard bytes != nil else {
            //Failed to allocate memory
            return []
        }

        guard self._listxattr(reference, namebuff: bytes, size: length, options: options) != -1 else {
            //There was an error, throw it
            throw Error(errno: errno)
        }

        let string = NSString(bytes: bytes, length: length, encoding: NSUTF8StringEncoding)
        let keys = string?.componentsSeparatedByString("\0").filter { !$0.isEmpty } ?? []

        return keys
    }

//MARK:- Attributes

    //TODO: Add doc
    public static func attributes(path path: String, options: Options=[]) throws -> [String: T.ValueType] {
        return try self.attributes(reference: .Path(path), options: options)
    }

    //TODO: Add doc
    public static func attributes(fd fd: Int32, options: Options=[]) throws -> [String: T.ValueType] {
        return try self.attributes(reference: .FileDescriptor(fd), options: options)
    }

    private static func attributes(reference reference: FileReference, options: Options) throws -> [String: T.ValueType] {
        return try self.keys(reference: reference, options: options).reduce([:]) { (dictionary, key) in
            var attrs = dictionary
            attrs[key] = try self.get(key, reference: reference, options: options)
            return attrs
        }
    }

//MARK:- C Function Wrappers

    private static func _getxattr(reference: FileReference, name: UnsafePointer<Int8>, value: UnsafeMutablePointer<Void>, size: Int, position: UInt32, options: Int32) -> Int {
        switch reference {
        case .Path(let path):
            return getxattr(path, name, value, size, position, options)
        case .FileDescriptor(let fd):
            return fgetxattr(fd, name, value, size, position, options)
        }
    }

    private static func _setxattr(reference: FileReference, name: UnsafePointer<Int8>, value: UnsafePointer<Void>, size: Int, position: UInt32, options: Int32) -> Int32 {
        switch reference {
        case .Path(let path):
            return setxattr(path, name, value, size, position, options)
        case .FileDescriptor(let fd):
            return fsetxattr(fd, name, value, size, position, options)
        }
    }

    private static func _removexattr(reference: FileReference, name: UnsafePointer<Int8>, options: Int32) -> Int32 {
        switch reference {
        case .Path(let path):
            return removexattr(path, name, options)
        case .FileDescriptor(let fd):
            return fremovexattr(fd, name, options)
        }
    }

    private static func _listxattr(reference: FileReference, namebuff: UnsafeMutablePointer<Int8>, size: Int, options: Int32) -> Int {
        switch reference {
        case .Path(let path):
            return listxattr(path, namebuff, size, options)
        case .FileDescriptor(let fd):
            return flistxattr(fd, namebuff, size, options)
        }
    }
}



//MARK:- FileReference

private enum FileReference {
    case Path(String)
    case FileDescriptor(Int32)
}

//MARK:- Options

public struct Options: OptionSetType {
    /// Do not follow symbolic links.
    ///
    /// Normally, `Xattr.get/set/remove/keys/attributes` acts on the target of `path` if it is a symbolic link.
    ///
    /// With this option, `Xattr.get/set/remove/keys/attributes` will act on the link itself.
    public static let NoFollow = Options(rawValue: XATTR_NOFOLLOW)

    /// HFS Plus Compression
    ///
    /// `Xattr.get/remove/keys/attributes` will act on HFS Plus Compression extended attribute `name` (if present) for the file referred to by `path` or `fd`.
    public static let ShowCompression = Options(rawValue: XATTR_SHOWCOMPRESSION)

    /// Force `Xattr.set` to fail if the named attribute already exists
    ///
    /// Failure to specify `Options.Replace` or `Options.Create` allows creation and replacement.
    public static let Create = Options(rawValue: XATTR_CREATE)

    /// Force `Xattr.set` to fail if the named attribute does not exist
    ///
    /// Failure to specify `Options.Replace` or `Options.Create` allows creation and replacement.
    public static let Replace = Options(rawValue: XATTR_REPLACE)

    public let rawValue: Int32
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// - Returns: Options set that is valid to use with **`getxattr`** function
    internal var getxattr: Options {
        return self.intersect([.NoFollow, .ShowCompression])
    }

    /// - Returns: Options set that is valid to use with **`removexattr`** function
    internal var removexattr: Options {
        return self.intersect([.NoFollow, .ShowCompression])
    }

    /// - Returns: Options set that is valid to use with **`listxattr`** function
    internal var listxattr: Options {
        return self.intersect([.NoFollow, .ShowCompression])
    }

    /// - Returns: Options set that is valid to use with **`setxattr`** function
    internal var setxattr: Options {
        return self.intersect([.NoFollow, .Create, .Replace])
    }
}

//MARK:- Limits

public struct Limits {
    public static let MaxNameLength = Int(XATTR_MAXNAMELEN)
    public static let MaxPathComponentLength = Int(NAME_MAX)
    public static let MaxPathLength = Int(PATH_MAX)
}

//MARK:- Error

public enum Error: ErrorType {

    /// **`ENOTSUP`** is raised by `getxattr`, `setxattr`, `removexattr` and `listxattr`
    case NotSupported
    /// **`EPERM`** is raised by `getxattr`, `setxattr`, `removexattr` and `listxattr`
    case Permission
    /// **`ENOTDIR`** is raised by `getxattr`, `setxattr`, `removexattr` and `listxattr`
    case NotDirectory
    /// **`ENAMETOOLONG`** is raised by `getxattr`, `setxattr`, `removexattr` and `listxattr`
    case NameTooLong
    /// **`EACCES`** is raised by `getxattr`, `setxattr`, `removexattr` and `listxattr`
    case Acces
    /// **`ELOOP`** is raised by `getxattr`, `setxattr`, `removexattr` and `listxattr`
    case Loop
    /// **`EFAULT`** is raised by `getxattr`, `setxattr`, `removexattr` and `listxattr`
    case Fault
    /// **`EIO`** is raised by `getxattr`, `setxattr`, `removexattr` and `listxattr`
    case IO
    /// **`EINVAL`** is raised by `getxattr`, `setxattr`, `removexattr` and `listxattr`
    case Invalid

    /// **`ENOATTR`** is raised by `getxattr`, `setxattr` and `removexattr`
    case NoAttribute

    /// **`ERANGE`** is raised by `getxattr`, `setxattr` and `listxattr`
    case Range

    /// **`EROFS`** is raised by `setxattr` and `removexattr`
    case ReadOnlyFileSystem

    /// **`EISDIR`** is raised by `getxattr`
    case IsDirectory

    /// **`EEXIST`** is raised by `setxattr`
    case Exist
    /// **`E2BIG`**  is raised by `setxattr`
    case TooBig
    /// **`ENOSPC`** is raised by `setxattr`
    case NoSpace

    /// Unknown error
    case Unknown(Int32)

    /// Looks up the error message string corresponding to the error code, as defined by `strerror` function
    ///
    /// - Returns: the error message, if available
    public var message: String? {
        let bytes = strerror(self.errno)
        guard bytes != nil else {
            return nil
        }

        return NSString(CString: bytes, encoding: NSUTF8StringEncoding) as? String
    }

    /// - Returns: Corresponding error code as defined in `/sys/errno.h`
    private var errno: Int32 {
        switch self {
        case .NoAttribute:          return ENOATTR
        case .NotSupported:         return ENOTSUP
        case .Range:                return ERANGE
        case .Permission:           return EPERM
        case .Invalid:              return EINVAL
        case .IsDirectory:          return EISDIR
        case .NotDirectory:         return ENOTDIR
        case .NameTooLong:          return ENAMETOOLONG
        case .Acces:                return EACCES
        case .Loop:                 return ELOOP
        case .Fault:                return EFAULT
        case .IO:                   return EIO
        case .Exist:                return EEXIST
        case .TooBig:               return E2BIG
        case .NoSpace:              return ENOSPC
        case .ReadOnlyFileSystem:   return EROFS
        case .Unknown(let errno):   return errno
        }
    }

    /// Initialize `Error` with error code as defined in `/sys/errno.h`
    ///
    /// If error code doesn't correspond to any enum case, initializes as `.Unknown(errno)`
    private init(errno: Int32) {
        switch errno {
        case ENOATTR:       self = .NoAttribute
        case ENOTSUP:       self = .NotSupported
        case ERANGE:        self = .Range
        case EPERM:         self = .Permission
        case EINVAL:        self = .Invalid
        case EISDIR:        self = .IsDirectory
        case ENOTDIR:       self = .NotDirectory
        case ENAMETOOLONG:  self = .NameTooLong
        case EACCES:        self = .Acces
        case ELOOP:         self = .Loop
        case EFAULT:        self = .Fault
        case EIO:           self = .IO
        case EEXIST:        self = .Exist
        case E2BIG:         self = .TooBig
        case ENOSPC:        self = .NoSpace
        case EROFS:         self = .ReadOnlyFileSystem
        default:            self = .Unknown(errno)
        }
    }
}

