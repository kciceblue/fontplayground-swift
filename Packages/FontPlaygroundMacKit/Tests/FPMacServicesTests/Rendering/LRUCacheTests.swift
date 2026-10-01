import Testing

@testable import FPMacServices

struct LRUCacheTests {
    @Test func recentlyReadEntriesSurviveEvictionAndRemoval() {
        let cache = LRUCache<Int, String>(capacity: 2)
        cache.insert("one", for: 1)
        cache.insert("two", for: 2)
        #expect(cache.value(for: 1) == "one")
        cache.insert("three", for: 3)
        #expect(cache.value(for: 2) == nil)
        cache.insert("updated", for: 1)
        cache.insert("four", for: 4)
        #expect(cache.value(for: 3) == nil)
        #expect(cache.value(for: 1) == "updated")
        cache.remove { $0 == 1 }
        #expect(cache.value(for: 1) == nil)
        #expect(cache.value(for: 4) == "four")
        cache.removeAll()
        #expect(cache.value(for: 4) == nil)
        cache.insert("five", for: 5)
        #expect(cache.value(for: 5) == "five")
        let disabled = LRUCache<Int, String>(capacity: 0)
        disabled.insert("zero", for: 0)
        #expect(disabled.value(for: 0) == nil)
    }
}
