import Foundation
import AgentLensCore

let base = URL(fileURLWithPath: "/private/tmp/agent-lens-m10b-implementation-9jaujmja/parent/qoder-r1-batch3/matrix")
let fixture = URL(fileURLWithPath: "/private/tmp/agent-lens-m10b-implementation-9jaujmja/fixture")
let prefix = base.appendingPathComponent("npm-prefix")
final class MatrixRunner: UpdateCommandRunner, @unchecked Sendable {
    let payload: Data
    let registry: String
    let scope: String
    let otherPrefix: Bool
    let changeRegistry: Bool
    private let lock = NSLock()
    private var viewCount = 0
    private var scopeCount = 0
    init(payload: Data, registry: String = "https://registry.npmjs.org/", scope: String = "undefined", otherPrefix: Bool = false, changeRegistry: Bool = false) {
        self.payload=payload; self.registry=registry; self.scope=scope; self.otherPrefix=otherPrefix; self.changeRegistry=changeRegistry
    }
    func count(_ a:[String]) -> Int { lock.lock(); defer { lock.unlock() }; if a.contains("view") { viewCount += 1 }; if a.contains("@openai:registry") { scopeCount += 1 }; return scopeCount }
    func views() -> Int { lock.lock(); defer { lock.unlock() }; return viewCount }
    func run(executablePath: String, arguments a:[String], environment:[String:String], timeout:TimeInterval) async -> CommandOutcome {
        let ordinal=count(a)
        let p=otherPrefix ? fixture.appendingPathComponent("npm-prefix") : prefix
        if a.contains("prefix") { return .success(Data((p.path+"\n").utf8)) }
        if a.contains("root") { return .success(Data((p.appendingPathComponent("lib/node_modules").path+"\n").utf8)) }
        if a.contains("view") { return .success(payload) }
        if a.contains("--version") { return .success(Data("10.9.8\n".utf8)) }
        if a.contains("@openai:registry") { return .success(Data(((changeRegistry && ordinal > 1) ? "https://changed.invalid/\n" : scope+"\n").utf8)) }
        if a.contains("registry") { return .success(Data((registry+"\n").utf8)) }
        return .failure(.invalidOutput)
    }
}
func json(_ version:String="2.0.0", latest:String?=nil) -> Data {
    try! JSONSerialization.data(withJSONObject:["name":"@openai/codex","version":version,"dist-tags.latest":latest ?? version])
}
@main struct Matrix {
    static func main() async throws {
        var raw=try JSONDecoder().decode([String:String].self,from:Data(contentsOf:fixture.appendingPathComponent("environment.json")))
        let paths=[prefix.appendingPathComponent("bin").path,fixture.appendingPathComponent("manager-bin").path,"/usr/bin","/bin"]
        raw["PATH"]=paths.joined(separator:":")
        let env=ShellEnvironment(shellPath:"/bin/zsh",pathEntries:paths,pathJoined:raw["PATH"]!,raw:raw,isDegraded:false)
        let def=try DetectorDefinition(id:"codex",displayName:"Codex",executableName:"codex",extraSearchRoots:[],fixture:nil,category:.aiAgent,packages:[try DeclaredPackage(manager:.npm,name:"@openai/codex")],informationURL:nil,uninstallInstructionsURL:nil,versionQuery:.standard)
        func run(_ label:String, _ runner:MatrixRunner, _ expected:String, views:Int, installed:String="1.0.0") async throws {
            let target=prefix.appendingPathComponent("lib/node_modules/@openai/codex/codex.sh")
            try Data(("#!/bin/sh\nprintf 'codex "+installed+"\\n'\n").utf8).write(to:target)
            try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:target.path)
            let diag=PathDiagnosticsScanner.scan(detector:def.makeDetector(),environment:env,currentDirectory:base.path)
            let cache=base.appendingPathComponent(label).appendingPathComponent("update-metadata-v1.json")
            let result=await NpmUpdateProbe.run(definition:def,diagnostic:diag,environment:env,runner:runner,cacheURL:cache,mode:.refresh,currentDirectory:base.path,now:{Date(timeIntervalSince1970:1000)},uptime:{1},stageDeadline:100,diagnosticIndex:0,npmScratchBaseURL:base.appendingPathComponent("scratch"))
            let status=String(describing:result.status)
            let persisted=FileManager.default.fileExists(atPath:cache.deletingLastPathComponent().appendingPathComponent("npm-update-metadata-v1.json").path)
            let passed=status.contains(expected) && runner.views()==views && (expected=="updateAvailable" || expected=="upToDate" || !persisted)
            FileHandle.standardOutput.write(Data("\(passed ? "PASS" : "FAIL") \(label): \(status), views=\(runner.views()), persisted=\(persisted)\n".utf8))
            if !passed { throw NSError(domain:"matrix",code:1,userInfo:[NSLocalizedDescriptionKey:label]) }
        }
        try await run("stable",MatrixRunner(payload:json()),"updateAvailable",views:1)
        try await run("two-prefix-mismatch",MatrixRunner(payload:json(),otherPrefix:true),"identityUnverified",views:0)
        try await run("custom-base-public-scope",MatrixRunner(payload:json(),registry:"https://private.invalid/",scope:"https://registry.npmjs.org/"),"unsupportedRegistry",views:0)
        try await run("credential-registry",MatrixRunner(payload:json(),registry:"https://user:secret@registry.npmjs.org/"),"unsupportedRegistry",views:0)
        try await run("registry-changed",MatrixRunner(payload:json(),changeRegistry:true),"unsupportedRegistry",views:1)
        try await run("multiple-json",MatrixRunner(payload:json()+Data("\n".utf8)+json()),"metadataInvalid",views:1)
        try await run("json-array",MatrixRunner(payload:Data("[]".utf8)),"metadataInvalid",views:1)
        try await run("wrong-value-type",MatrixRunner(payload:Data("{\"name\":\"@openai/codex\",\"version\":2,\"dist-tags.latest\":\"2.0.0\"}".utf8)),"metadataInvalid",views:1)
        try await run("invalid-utf8",MatrixRunner(payload:Data([0xff,0xfe])),"metadataInvalid",views:1)
        try await run("oversize",MatrixRunner(payload:Data(repeating:32,count:1_048_577)),"metadataInvalid",views:1)
        try await run("prerelease-latest",MatrixRunner(payload:json("2.0.0-beta.1")),"unsupportedChannel",views:1)
        try await run("prerelease-installed",MatrixRunner(payload:json("1.0.0")),"updateAvailable",views:1,installed:"1.0.0-beta.1")
        try await run("large-numeric",MatrixRunner(payload:json("999999999999999999999999999999999999999.0.0")),"updateAvailable",views:1)
        try await run("ahead",MatrixRunner(payload:json("0.9.0")),"unknown",views:1)
        try await run("invalid-version",MatrixRunner(payload:json("2.0")),"metadataInvalid",views:1)
        print("MATRIX COMPLETE")
    }
}
