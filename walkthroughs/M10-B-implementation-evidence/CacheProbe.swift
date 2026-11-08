import Foundation
import AgentLensCore
@main struct CacheProbe {
 static func main() throws {
    let root=URL(fileURLWithPath:"/private/tmp/agent-lens-m10b-implementation-9jaujmja/parent/qoder-r1-batch3/cache-repro");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let cache=NpmUpdateMetadataCache(updateCacheURL:root.appendingPathComponent("update-metadata-v1.json"),now:{Date(timeIntervalSince1970:1000)})
    func entry(_ id:String,_ version:String="2.0.0",_ latest:String="2.0.0") -> NpmUpdateMetadataEntry {
        NpmUpdateMetadataEntry(registryID:id,package:"@openai/codex",registry:"https://registry.npmjs.org/",tag:"latest",managerEntryPath:"/manager/npm",managerTarget:"/manager/npm",managerFingerprint:"manager",prefix:"/prefix",installationRoot:"/prefix/lib/node_modules/@openai/codex",selectedEntryPath:"/prefix/bin/codex",selectedTarget:"/prefix/lib/node_modules/@openai/codex/codex.js",selectedFingerprint:"selected",proofFingerprint:"proof",contextDigest:"context",name:"@openai/codex",version:version,distTagsLatest:latest,observedAt:Date(timeIntervalSince1970:999))
    }
    let a=entry("A"),b=entry("B"),poison=entry("A","2.0.0","9.0.0")
    let key=NpmUpdateMetadataKey(registryID:a.registryID,package:a.package,registry:a.registry,tag:a.tag,managerEntryPath:a.managerEntryPath,managerTarget:a.managerTarget,managerFingerprint:a.managerFingerprint,prefix:a.prefix,installationRoot:a.installationRoot,selectedEntryPath:a.selectedEntryPath,selectedTarget:a.selectedTarget,selectedFingerprint:a.selectedFingerprint,proofFingerprint:a.proofFingerprint,contextDigest:a.contextDigest)
    let array=try [a,poison].map{try JSONSerialization.jsonObject(with:JSONEncoder().encode($0))}
    try JSONSerialization.data(withJSONObject:["schemaVersion":1,"entries":array],options:.sortedKeys).write(to:cache.fileURL)
    print("before-unrelated-save hit=\(cache.lookup(key) != nil)")
    print("save-B success=\(cache.save([b]))")
    print("after-unrelated-save hit=\(cache.lookup(key) != nil)")
 }
}
