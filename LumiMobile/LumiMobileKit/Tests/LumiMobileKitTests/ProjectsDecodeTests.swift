import XCTest
@testable import LumiMobileKit

final class ProjectsDecodeTests: XCTestCase {
    func testProjectsMessageDecodes() {
        let frame = """
        {"v":1,"type":"projects","payload":{
          "projects":[{"name":"unco-forge","path":"/p/unco","checkouts":[
            {"kind":"original","title":"main","scm":"git","path":"/p/unco","agentIds":["t1","t2"]},
            {"kind":"workspace","title":"review","branch":"feat/review","scm":"git","path":"/p/wt","agentIds":["t3"]}
          ]}],
          "addable":[{"name":"orca","path":"/p/orca"}]
        }}
        """
        guard case .projects(let snap)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("expected .projects")
        }
        XCTAssertEqual(snap.projects.count, 1)
        XCTAssertEqual(snap.projects[0].checkouts.count, 2)
        XCTAssertEqual(snap.projects[0].checkouts[0].agentIds, ["t1", "t2"])
        XCTAssertEqual(snap.projects[0].checkouts[1].branch, "feat/review")
        XCTAssertEqual(snap.addable.map(\.path), ["/p/orca"])
    }

    /// Mac decision 108/114: additive `others` — loose terminals by folder.
    func testProjectsDecodesOtherGroupsAndToleratesTheirAbsence() {
        let frame = """
        {"v":1,"type":"projects","payload":{"projects":[],
          "others":[{"path":"/Users/me/Desktop","label":"~/Desktop","agentIds":["t9"]},{"path":"/tmp"}]
        }}
        """
        guard case .projects(let snap)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("expected .projects")
        }
        XCTAssertEqual(snap.others.map(\.label), ["~/Desktop", "/tmp"], "label falls back to path")
        XCTAssertEqual(snap.others[0].agentIds, ["t9"])
        XCTAssertEqual(snap.others[1].agentIds, [])

        let old = #"{"v":1,"type":"projects","payload":{"projects":[]}}"#
        guard case .projects(let oldSnap)? = PhoneProtocol.decodeServerMessage(old) else {
            return XCTFail("expected .projects")
        }
        XCTAssertTrue(oldSnap.others.isEmpty, "older Mac omits others")
    }

    func testProjectsToleratesMissingAddableAndUnknownEnums() {
        let frame = """
        {"v":1,"type":"projects","payload":{"projects":[
          {"name":"x","path":"/x","checkouts":[
            {"kind":"future-kind","title":"main","scm":"svn","path":"/x","agentIds":[]}
          ]}
        ]}}
        """
        guard case .projects(let snap)? = PhoneProtocol.decodeServerMessage(frame) else {
            return XCTFail("expected .projects")
        }
        XCTAssertTrue(snap.addable.isEmpty)
        XCTAssertEqual(snap.projects[0].checkouts[0].kind, "future-kind")
        XCTAssertEqual(snap.projects[0].checkouts[0].scm, "svn")
    }

    func testSessionMetaDecodesWithAndWithoutNewFields() {
        let withFields = """
        {"v":1,"type":"sessions","payload":{"sessions":[
          {"id":"t1","repoName":"r","status":"idle","cols":80,"rows":24,"provider":"claude","lastActivityAt":1790000000000}
        ]}}
        """
        guard case .sessions(let a)? = PhoneProtocol.decodeServerMessage(withFields) else {
            return XCTFail("sessions")
        }
        XCTAssertEqual(a[0].provider, "claude")
        XCTAssertEqual(a[0].lastActivityAt, 1_790_000_000_000)

        let withoutFields = """
        {"v":1,"type":"sessions","payload":{"sessions":[
          {"id":"t2","repoName":"r","status":"idle","cols":80,"rows":24}
        ]}}
        """
        guard case .sessions(let b)? = PhoneProtocol.decodeServerMessage(withoutFields) else {
            return XCTFail("sessions")
        }
        XCTAssertNil(b[0].provider)
        XCTAssertNil(b[0].lastActivityAt)
    }
}
