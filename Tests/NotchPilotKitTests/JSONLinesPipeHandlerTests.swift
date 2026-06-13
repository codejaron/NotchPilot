import XCTest
@testable import NotchPilotKit

final class JSONLinesPipeHandlerTests: XCTestCase {
    func testBuffersUTF8CharactersSplitAcrossChunks() async {
        let handler = JSONLinesPipeHandler()
        let recorder = JSONLineRecorder()
        let decodedLine = expectation(description: "decoded split UTF-8 line")

        Task {
            await handler.readJSONLines(as: JSONLineFixture.self) { value in
                await recorder.append(value)
                decodedLine.fulfill()
            }
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        let lineData = Data(#"{"title":"歌名"}"#.utf8) + Data([0x0A])
        let splitIndex = try! XCTUnwrap(indexSplittingFirstMultibyteCharacter(in: lineData))
        handler.pipe.fileHandleForWriting.write(lineData.prefix(splitIndex))
        await Task.yield()
        handler.pipe.fileHandleForWriting.write(lineData.dropFirst(splitIndex))

        await fulfillment(of: [decodedLine], timeout: 1)
        let values = await recorder.values()
        XCTAssertEqual(values, [JSONLineFixture(title: "歌名")])

        await handler.close()
    }

    func testCloseResumesPendingReader() async {
        let handler = JSONLinesPipeHandler()
        let readerFinished = expectation(description: "reader finished")

        Task {
            await handler.readJSONLines(as: JSONLineFixture.self) { _ in
                XCTFail("No lines should be decoded")
            }
            readerFinished.fulfill()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        await handler.close()

        await fulfillment(of: [readerFinished], timeout: 1)
    }

    private func indexSplittingFirstMultibyteCharacter(in data: Data) -> Int? {
        let bytes = Array(data)
        guard let firstContinuationIndex = bytes.firstIndex(where: { ($0 & 0xC0) == 0x80 }) else {
            return nil
        }
        return firstContinuationIndex
    }
}

private struct JSONLineFixture: Decodable, Equatable, Sendable {
    let title: String
}

private actor JSONLineRecorder {
    private var recordedValues: [JSONLineFixture] = []

    func values() -> [JSONLineFixture] {
        recordedValues
    }

    func append(_ value: JSONLineFixture) {
        recordedValues.append(value)
    }
}
