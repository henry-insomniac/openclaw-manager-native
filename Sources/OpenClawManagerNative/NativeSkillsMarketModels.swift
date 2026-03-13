@preconcurrency import Foundation

enum SkillsMarketSort: String, CaseIterable, Identifiable, Codable, Sendable {
    case downloads
    case updated
    case stars
    case installsCurrent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads:
            return "下载量"
        case .updated:
            return "最近更新"
        case .stars:
            return "Stars"
        case .installsCurrent:
            return "当前安装"
        }
    }
}

struct OpenClawSkillsMarketSummary: Decodable, Equatable, Sendable {
    struct Category: Decodable, Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        var count: Int
    }

    struct Item: Decodable, Equatable, Identifiable, Sendable {
        var slug: String
        var name: String
        var summary: String
        var summaryZh: String?
        var owner: String?
        var githubUrl: String?
        var registryUrl: String
        var categoryIds: [String]
        var tags: [String]
        var downloads: Int?
        var stars: Int?
        var installsCurrent: Int?
        var updatedAt: String?

        var id: String { slug }

        var preferredSummary: String {
            let localized = summaryZh?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !localized.isEmpty {
                return localized
            }
            return summary
        }
    }

    var collectedAt: String
    var sourceRepo: String
    var managedDirectory: String
    var totalItems: Int
    var categories: [Category]
    var items: [Item]
}

struct OpenClawSkillsInventory: Decodable, Equatable, Sendable {
    struct Item: Decodable, Equatable, Identifiable, Sendable {
        var slug: String
        var name: String
        var summary: String
        var source: String
        var runtimeSource: String?
        var runtimeStatus: String?
        var enabled: Bool?
        var eligible: Bool?
        var bundled: Bool
        var managerOwned: Bool
        var uninstallable: Bool
        var visibleInRuntime: Bool
        var homepage: String?
        var installedVersion: String?
        var installedAt: String?
        var originRegistry: String?

        var id: String { slug }
    }

    var collectedAt: String
    var managedDirectory: String
    var lockPath: String
    var runtimeError: String?
    var totalItems: Int
    var managerInstalled: Int
    var personalInstalled: Int
    var bundledInstalled: Int
    var workspaceInstalled: Int
    var globalInstalled: Int
    var externalInstalled: Int
    var items: [Item]
}

struct OpenClawSkillMarketDetail: Decodable, Equatable, Sendable {
    struct Stats: Decodable, Equatable, Sendable {
        var comments: Int
        var downloads: Int
        var installsAllTime: Int
        var installsCurrent: Int
        var stars: Int
        var versions: Int
    }

    struct LatestVersion: Decodable, Equatable, Sendable {
        var version: String?
        var createdAt: String?
        var changelog: String?
        var license: String?
    }

    struct Metadata: Decodable, Equatable, Sendable {
        var os: [String]
        var systems: [String]
    }

    struct Owner: Decodable, Equatable, Sendable {
        var handle: String?
        var displayName: String?
        var image: String?
    }

    struct Moderation: Decodable, Equatable, Sendable {
        var verdict: String
        var isSuspicious: Bool
        var isMalwareBlocked: Bool
        var reasonCodes: [String]
        var summary: String?
        var updatedAt: String?
    }

    var collectedAt: String
    var item: OpenClawSkillsMarketSummary.Item
    var createdAt: String?
    var updatedAt: String?
    var stats: Stats
    var latestVersion: LatestVersion?
    var metadata: Metadata
    var owner: Owner?
    var moderation: Moderation?
}

struct OpenClawSkillMutationResult: Decodable, Equatable, Sendable {
    var ok: Bool
    var action: String
    var slug: String
    var message: String
    var installDirectory: String?
    var installedVersion: String?
}

struct OpenClawSkillsConfigMutationResult: Decodable, Equatable, Sendable {
    var ok: Bool
    var action: String
    var path: String
    var message: String
    var configPath: String
}
