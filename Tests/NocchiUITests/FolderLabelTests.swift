import Foundation
import Testing
@testable import NocchiUI

@MainActor
@Suite struct FolderLabelTests {
    let home = FileManager.default.homeDirectoryForCurrentUser.path

    @Test func folderAndParent() {
        #expect(FolderPicker.label(URL(fileURLWithPath: "/Users/me/code/acme/webapp")) == "acme/webapp")
        #expect(FolderPicker.label(URL(fileURLWithPath: "\(home)/Projects/nocchi")) == "~/Projects/nocchi")
    }

    @Test func shortPathsStayWhole() {
        #expect(FolderPicker.label(URL(fileURLWithPath: home)) == "~")
        #expect(FolderPicker.label(URL(fileURLWithPath: "\(home)/Projects")) == "~/Projects")
        #expect(FolderPicker.label(URL(fileURLWithPath: "/tmp")) == "/tmp")
        #expect(FolderPicker.label(URL(fileURLWithPath: "/Volumes/Data")) == "/Volumes/Data")
    }

    @Test func lookalikesGetMoreParents() {
        let mine = URL(fileURLWithPath: "/Volumes/Data/a/acme/webapp")
        let fork = URL(fileURLWithPath: "/Volumes/Old/a/acme/webapp")
        #expect(FolderPicker.label(mine, among: [mine, fork]) == "Data/a/acme/webapp")
    }
}
