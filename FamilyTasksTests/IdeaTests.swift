import XCTest
@testable import FamilyTasks

@MainActor
final class IdeaTests: XCTestCase {
    func testIdeasSavedBeforeKindsStillLoad() throws {
        let old = #"[{"id":"6B1A3C3E-5A0B-4C3B-9D7E-1F2A3B4C5D6E","title":"Balboa Park","notes":"","link":"","tags":["Outdoor"],"createdAt":700000000,"updatedAt":700000000}]"#
        let ideas = try JSONDecoder().decode([IdeaNote].self, from: Data(old.utf8))
        XCTAssertEqual(ideas.first?.kind, .other)
        XCTAssertEqual(ideas.first?.tags, ["Outdoor"])
        XCTAssertFalse(ideas.first?.isDone ?? true)

        var idea = try XCTUnwrap(ideas.first)
        idea.kind = .place
        idea.doneAt = Date(timeIntervalSince1970: 1_800_000_000)
        idea.rating = 4
        let roundTrip = try JSONDecoder().decode(IdeaNote.self, from: JSONEncoder().encode(idea))
        XCTAssertEqual(roundTrip, idea)
    }

    func testKindIsGuessedFromTheLinkAndTitle() {
        XCTAssertEqual(IdeaKind.guess(link: URL(string: "https://maps.apple.com/?q=Balboa%20Park"), text: ""), .place)
        XCTAssertEqual(IdeaKind.guess(link: URL(string: "https://www.google.com/maps/place/Balboa+Park"), text: ""), .place)
        XCTAssertEqual(IdeaKind.guess(link: URL(string: "https://maps.app.goo.gl/abc123"), text: ""), .place)
        XCTAssertEqual(IdeaKind.guess(link: URL(string: "https://youtu.be/abc"), text: "Easy chicken biryani recipe"), .food)
        XCTAssertEqual(IdeaKind.guess(link: URL(string: "https://www.youtube.com/watch?v=abc"), text: "Full movie review"), .watch)
        XCTAssertEqual(IdeaKind.guess(link: URL(string: "https://x.com/someone/status/1"), text: "Look at this"), .other)
    }

    func testPagePreviewReadsOpenGraphTags() {
        let html = """
        <html><head>
        <title>Fallback title</title>
        <meta content="Tacos &amp; More &#8212; Best in SD" property="og:title">
        <meta property='og:image' content='/images/taco.jpg'>
        <meta name="description" content="Street tacos   in Old Town">
        <meta property="og:site_name" content="Yelp">
        </head></html>
        """
        let preview = LinkPreview.parse(html: html, baseURL: URL(string: "https://www.yelp.com/biz/tacos")!)
        XCTAssertEqual(preview.title, "Tacos & More — Best in SD")
        XCTAssertEqual(preview.imageURL, "https://www.yelp.com/images/taco.jpg")
        XCTAssertEqual(preview.summary, "Street tacos in Old Town")
        XCTAssertEqual(preview.siteName, "Yelp")

        XCTAssertEqual(LinkPreview.parse(html: "<title>Just a title</title>", baseURL: URL(string: "https://a.com")!).title, "Just a title")
    }

    func testLinksKnowTheirVideoAndPlace() {
        XCTAssertEqual(LinkPreview.youTubeID(in: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=xyz")!), "dQw4w9WgXcQ")
        XCTAssertEqual(LinkPreview.youTubeID(in: URL(string: "https://youtu.be/dQw4w9WgXcQ?si=xyz")!), "dQw4w9WgXcQ")
        XCTAssertEqual(LinkPreview.youTubeID(in: URL(string: "https://youtube.com/shorts/abc123")!), "abc123")
        XCTAssertNil(LinkPreview.youTubeID(in: URL(string: "https://vimeo.com/123")!))

        let apple = LinkPreview.mapPlace(in: URL(string: "https://maps.apple.com/?ll=32.7341,-117.1446&q=Balboa%20Park")!)
        XCTAssertEqual(apple?.name, "Balboa Park")
        XCTAssertEqual(apple?.latitude ?? 0, 32.7341, accuracy: 0.0001)

        let google = LinkPreview.mapPlace(in: URL(string: "https://www.google.com/maps/place/San+Diego+Zoo/@32.7353,-117.149,17z/data=x")!)
        XCTAssertEqual(google?.name, "San Diego Zoo")
        XCTAssertEqual(google?.longitude ?? 0, -117.149, accuracy: 0.0001)
        XCTAssertNil(LinkPreview.mapPlace(in: URL(string: "https://www.youtube.com/watch?v=a")!))
    }

    func testSharedTextSplitsTheLinkFromTheName() {
        let shared = SharedLinkText.split("Balboa Park\n1549 El Prado, San Diego, CA\nhttps://maps.app.goo.gl/abc123")
        XCTAssertEqual(shared.url?.absoluteString, "https://maps.app.goo.gl/abc123")
        XCTAssertEqual(shared.rest, "Balboa Park\n1549 El Prado, San Diego, CA")
        XCTAssertNil(SharedLinkText.split("Just words").url)
    }

    func testSameLinkIgnoresTrackingBits() {
        XCTAssertTrue(IdeaNote.sameLink("https://www.youtube.com/watch?v=abc&si=123", "https://youtube.com/watch?v=abc"))
        XCTAssertTrue(IdeaNote.sameLink("https://www.instagram.com/reel/xyz/?igsh=foo", "https://instagram.com/reel/xyz"))
        XCTAssertFalse(IdeaNote.sameLink("https://youtube.com/watch?v=abc", "https://youtube.com/watch?v=def"))
        XCTAssertFalse(IdeaNote.sameLink("", ""))
    }

    func testSharedIdeasAreTakenInOnceWithoutDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inbox = IdeaInbox(directory: directory)
        let store = OrganizerStore(directory: directory)
        store.addIdea({
            var draft = IdeaDraft()
            draft.title = "Already saved"
            draft.link = "https://youtube.com/watch?v=abc"
            return draft
        }())

        try inbox.add(IdeaNote(title: "Same video", link: "https://www.youtube.com/watch?v=abc&si=share"))
        try inbox.add(IdeaNote(title: "Balboa Park", link: "https://maps.apple.com/?q=Balboa%20Park", kind: .place, location: "Balboa Park"))

        let added = store.takeSharedIdeas(from: inbox)
        XCTAssertEqual(added.map(\.title), ["Balboa Park"])
        XCTAssertEqual(store.ideaNotes.count, 2)
        XCTAssertTrue(inbox.pending().isEmpty, "Everything is cleared, duplicates too")
        XCTAssertTrue(store.takeSharedIdeas(from: inbox).isEmpty)
    }

    func testDoneRatingAndPreviewFill() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = OrganizerStore(directory: directory)
        var draft = IdeaDraft()
        draft.title = "Dosa place"
        draft.kind = .place
        draft.link = "https://maps.apple.com/?q=Dosa"
        let idea = try XCTUnwrap(store.addIdea(draft))

        store.applyPreview(LinkPreview(title: "Ignored", imageURL: "https://img/x.jpg", siteName: "Apple Maps", place: .init(name: "Dosa Hut", latitude: 1, longitude: 2)), to: idea.id)
        var saved = try XCTUnwrap(store.ideaNotes.first)
        XCTAssertEqual(saved.title, "Dosa place", "A preview never renames")
        XCTAssertEqual(saved.imageURL, "https://img/x.jpg")
        XCTAssertEqual(saved.location, "Dosa Hut")

        store.setIdeaDone(saved, true, at: Date(timeIntervalSince1970: 1_800_000_000))
        saved = try XCTUnwrap(store.ideaNotes.first)
        store.rateIdea(saved, stars: 9)
        saved = try XCTUnwrap(store.ideaNotes.first)
        XCTAssertEqual(saved.rating, 5)
        XCTAssertEqual(saved.doneAt, Date(timeIntervalSince1970: 1_800_000_000))

        store.setIdeaDone(saved, false)
        saved = try XCTUnwrap(store.ideaNotes.first)
        XCTAssertNil(saved.doneAt)
        XCTAssertNil(saved.rating)
    }
}
