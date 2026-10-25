import Foundation
import LumiKit
import XCTest

/// Pre-signed görsel adresleri her listede yeniden imzalanır; kimlik imzadan
/// bağımsız olmalı ki görsel bir kez insin.
final class TaskImageIdentityTests: XCTestCase {
    func testS3SignatureParametersAreIgnored() {
        let first = URL(string: "https://b.s3.amazonaws.com/r/a/shot.png?X-Amz-Date=1&X-Amz-Signature=aa&x-id=GetObject")!
        let second = URL(string: "https://b.s3.amazonaws.com/r/a/shot.png?X-Amz-Date=2&X-Amz-Signature=bb&x-id=GetObject")!
        XCTAssertEqual(TaskImageIdentity.key(for: first), TaskImageIdentity.key(for: second))
        XCTAssertEqual(TaskImageIdentity.key(for: first), "https://b.s3.amazonaws.com/r/a/shot.png?x-id=GetObject")
    }

    func testCloudFrontAndGoogleSignaturesAreIgnored() {
        XCTAssertEqual(
            TaskImageIdentity.key(for: URL(string: "https://cdn.x/a.png?Expires=1&Signature=s&Key-Pair-Id=k")!),
            "https://cdn.x/a.png"
        )
        XCTAssertEqual(
            TaskImageIdentity.key(for: URL(string: "https://storage.googleapis.com/b/a.png?X-Goog-Signature=s")!),
            "https://storage.googleapis.com/b/a.png"
        )
    }

    func testParametersThatSelectTheImageAreKept() {
        let one = TaskImageIdentity.key(for: URL(string: "https://srv.x/img?id=1")!)
        let two = TaskImageIdentity.key(for: URL(string: "https://srv.x/img?id=2")!)
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(TaskImage(url: URL(string: "https://srv.x/img?id=1")!).id, one)
    }
}
