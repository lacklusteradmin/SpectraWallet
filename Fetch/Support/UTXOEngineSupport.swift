import Foundation

extension Data {
    init?(hexEncoded string: String) {
        let evenLengthString = string.count.isMultiple(of: 2) ? string : "0" + string
        var data = Data(capacity: evenLengthString.count / 2)
        var index = evenLengthString.startIndex

        for _ in 0 ..< evenLengthString.count / 2 {
            let nextIndex = evenLengthString.index(index, offsetBy: 2)
            let byteString = evenLengthString[index ..< nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
