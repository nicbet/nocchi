import Foundation
import Testing
@testable import NocchiUI

@MainActor
@Suite struct FolderLabelTests {
    let home = FileManager.default.homeDirectoryForCurrentUser.path

    @Test func folderAndParent() {
        #expect(FolderLabel.short(URL(fileURLWithPath: "/Users/me/code/acme/webapp")) == "acme/webapp")
        #expect(FolderLabel.short(URL(fileURLWithPath: "\(home)/Projects/nocchi")) == "~/Projects/nocchi")
    }

    @Test func shortPathsStayWhole() {
        #expect(FolderLabel.short(URL(fileURLWithPath: home)) == "~")
        #expect(FolderLabel.short(URL(fileURLWithPath: "\(home)/Projects")) == "~/Projects")
        #expect(FolderLabel.short(URL(fileURLWithPath: "/tmp")) == "/tmp")
        #expect(FolderLabel.short(URL(fileURLWithPath: "/Volumes/Data")) == "/Volumes/Data")
    }

    @Test func lookalikesGetMoreParents() {
        let mine = URL(fileURLWithPath: "/Volumes/Data/a/acme/webapp")
        let fork = URL(fileURLWithPath: "/Volumes/Old/a/acme/webapp")
        #expect(FolderLabel.short(mine, among: [mine, fork]) == "Data/a/acme/webapp")
    }
}
