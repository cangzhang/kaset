import Foundation
import FoundationModels
import Testing
@testable import Kaset

// MARK: - MusicIntent Integration Tests

/// Integration tests that call the actual Apple Intelligence LLM.
///
/// These tests validate that natural language prompts are correctly parsed
/// into `MusicIntent` structs. They require macOS 26+ with Apple Intelligence.
///
/// ## Flakiness Mitigation
///
/// LLM outputs are inherently non-deterministic. These tests mitigate flakiness by:
/// 1. **Retry logic**: Each test retries up to 3 times before failing
/// 2. **Relaxed matching**: Checks multiple fields (e.g., mood OR query) for expected content
/// 3. **Case-insensitive**: All string comparisons are lowercased
/// 4. **Fresh sessions**: Each attempt uses a new `LanguageModelSession` to avoid context drift
///
/// ## Running These Tests
///
/// Run only integration tests:
/// ```bash
/// xcodebuild test -scheme Kaset -destination 'platform=macOS' \
///   -only-testing:KasetTests/MusicIntentIntegrationTests
/// ```
///
/// Run all unit tests EXCEPT integration tests:
/// ```bash
/// xcodebuild test -scheme Kaset -destination 'platform=macOS' \
///   -only-testing:KasetTests -skip-testing:KasetTests/MusicIntentIntegrationTests
/// ```
///
/// Skip by tag (recommended for CI):
/// ```bash
/// xcodebuild test -scheme Kaset -destination 'platform=macOS' \
///   -only-testing:KasetTests -skip-test-tag integration
/// ```
@Suite("MusicIntent Integration", .tags(.integration, .slow), .serialized)
@MainActor
struct MusicIntentIntegrationTests {
  // MARK: - Constants

  /// Maximum number of retry attempts for flaky LLM calls.
  private static let maxRetries = 3

    /// System prompt for intent parsing - kept minimal to fit in context window.
    private static let systemPrompt = """
        Parse music commands into MusicIntent. Actions: play, queue, shuffle, like, dislike, \
        skip, previous, pause, resume, search. Fields: query, artist, genre, mood, era, version, activity.
        """

  // MARK: - Test Helpers

    /// Parses a natural language prompt into a MusicIntent using the LLM.
    /// Creates a fresh session per call to avoid context window overflow.
    private func parseIntent(from prompt: String) async throws -> MusicIntent {
        guard SystemLanguageModel.default.availability == .available else {
            throw AIUnavailableError()
        }
        // Create a fresh session each time to avoid context accumulation
        let session = LanguageModelSession(instructions: Self.systemPrompt)
        let response = try await session.respond(to: prompt, generating: MusicIntent.self)
        return response.content
    }

  /// Retries a test assertion up to `maxRetries` times to handle LLM non-determinism.
  ///
  /// - Parameters:
  ///   - maxAttempts: Maximum number of attempts (defaults to `maxRetries`)
  ///   - operation: The async operation that returns a value to validate
  ///   - validate: A closure that validates the result and throws if invalid
  /// - Throws: The last validation error if all attempts fail
  private func withRetry<T>(
    maxAttempts: Int = maxRetries,
    operation: () async throws -> T,
    validate: (T) throws -> Void
  ) async throws {
    var lastError: Error?

    for attempt in 1...maxAttempts {
      do {
        let result = try await operation()
        try validate(result)
        return  // Success
      } catch is AIUnavailableError {
        throw AIUnavailableError()  // Don't retry unavailability
      } catch {
        lastError = error
        if attempt < maxAttempts {
          // Brief delay before retry to avoid rate limiting
          try await Task.sleep(for: .milliseconds(500))
        }
      }
    }

    throw lastError ?? AIUnavailableError()
  }

  // MARK: - Basic Actions (Parameterized)

    @Test("Parses playback control commands", arguments: [
        (prompt: "Play music", expectedAction: MusicAction.play),
        (prompt: "Skip this song", expectedAction: MusicAction.skip),
      (prompt: "Skip to next track", expectedAction: MusicAction.skip),
      (prompt: "Pause the music", expectedAction: MusicAction.pause),
      (prompt: "Resume the paused music", expectedAction: MusicAction.resume),
        (prompt: "Like this song", expectedAction: MusicAction.like),
        (prompt: "Add jazz to queue", expectedAction: MusicAction.queue),
    ])
    func parsePlaybackCommand(prompt: String, expectedAction: MusicAction) async throws {
    try await withRetry {
      try await parseIntent(from: prompt)
    } validate: { intent in
      #expect(intent.action == expectedAction)
    }
    }

    // MARK: - Content Queries (Parameterized)

    @Test("Parses mood-based queries", arguments: [
        (prompt: "Play something chill", expected: "chill"),
        (prompt: "Play upbeat music", expected: "upbeat"),
    ])
    func parseMoodQuery(prompt: String, expected: String) async throws {
    try await withRetry {
      try await parseIntent(from: prompt)
    } validate: { intent in
      #expect(intent.action == .play)
      let combined = "\(intent.mood) \(intent.query)".lowercased()
      #expect(
        combined.contains(expected), "Expected '\(expected)' in mood or query, got: \(combined)")
    }
    }

    @Test("Parses genre queries", arguments: [
        (prompt: "Play jazz", expected: "jazz"),
        (prompt: "Play some rock", expected: "rock"),
    ])
    func parseGenreQuery(prompt: String, expected: String) async throws {
    try await withRetry {
      try await parseIntent(from: prompt)
    } validate: { intent in
      #expect(intent.action == .play)
      let combined = "\(intent.genre) \(intent.query)".lowercased()
      #expect(
        combined.contains(expected), "Expected '\(expected)' in genre or query, got: \(combined)")
    }
    }

    @Test("Parses era/decade queries", arguments: [
        (prompt: "Play 80s hits", expected: "80"),
        (prompt: "Play 90s music", expected: "90"),
    ])
    func parseEraQuery(prompt: String, expected: String) async throws {
    try await withRetry {
      try await parseIntent(from: prompt)
    } validate: { intent in
      #expect(intent.action == .play)
      let combined = "\(intent.era) \(intent.query)".lowercased()
      #expect(
        combined.contains(expected), "Expected '\(expected)' in era or query, got: \(combined)")
    }
    }

    @Test("Parses artist queries", arguments: [
        (prompt: "Play Beatles", expected: "beatles"),
        (prompt: "Play Taylor Swift songs", expected: "taylor"),
    ])
    func parseArtistQuery(prompt: String, expected: String) async throws {
    try await withRetry {
      try await parseIntent(from: prompt)
    } validate: { intent in
      #expect(intent.action == .play)
      let combined = "\(intent.artist) \(intent.query)".lowercased()
      #expect(
        combined.contains(expected), "Expected '\(expected)' in artist or query, got: \(combined)")
    }
    }

    @Test("Parses activity-based queries", arguments: [
        (prompt: "Play music for studying", expected: "study"),
        (prompt: "Play workout songs", expected: "workout"),
    ])
    func parseActivityQuery(prompt: String, expected: String) async throws {
    try await withRetry {
      try await parseIntent(from: prompt)
    } validate: { intent in
      #expect(intent.action == .play)
      // LLM may place activity keywords in activity, mood, genre, or query fields
      let combined = "\(intent.activity) \(intent.mood) \(intent.genre) \(intent.query)"
        .lowercased()
      #expect(
        combined.contains(expected),
        "Expected '\(expected)' in activity, mood, genre, or query, got: \(combined)")
    }
    }

    // MARK: - Complex Query

    @Test("Parses complex multi-component query")
    func parseComplexQuery() async throws {
    try await withRetry {
      try await parseIntent(from: "Play chill jazz from the 80s")
    } validate: { intent in
      #expect(intent.action == .play)
      let components = [intent.mood, intent.genre, intent.era].filter { !$0.isEmpty }
      #expect(components.count >= 2, "Expected at least 2 components populated, got: \(components)")
    }
    }

    @Test("Parses version type query")
    func parseVersionQuery() async throws {
    try await withRetry {
      try await parseIntent(from: "Play acoustic covers")
    } validate: { intent in
      #expect(intent.action == .play)
      let combined = "\(intent.version) \(intent.query)".lowercased()
      #expect(
        combined.contains("acoustic"), "Expected 'acoustic' in version or query, got: \(combined)")
    }
    }
}

// MARK: - AIUnavailableError

/// Error thrown when Apple Intelligence is not available.
/// Tests catching this error should be considered skipped.
struct AIUnavailableError: Error, CustomStringConvertible {
    var description: String { "Apple Intelligence not available on this device" }
}
