import CoolifyAPI
import Foundation

/// Where a new application's code comes from. Each one is a screen of the New Resource sheet.
enum NewApplicationSource: String, CaseIterable, Identifiable, Hashable {
    case publicGit
    case dockerfile
    case dockerImage
    case githubApp
    case deployKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicGit: "Public Git repository"
        case .dockerfile: "Dockerfile"
        case .dockerImage: "Docker image"
        case .githubApp: "Private GitHub App"
        case .deployKey: "Deploy key"
        }
    }

    var slogan: String {
        switch self {
        case .publicGit: "A repository anyone can clone, on the branch you name."
        case .dockerfile: "Paste a Dockerfile. Coolify builds it and runs the image."
        case .dockerImage: "An image that already exists in a registry."
        case .githubApp: "A private repository through a GitHub App on this instance."
        case .deployKey: "A private repository cloned with a key this instance already has."
        }
    }
}

extension ApplicationBuildPack {
    var displayName: String {
        switch self {
        case .nixpacks: "Nixpacks"
        case .railpack: "Railpack"
        case .static: "Static"
        case .dockerfile: "Dockerfile"
        case .dockercompose: "Docker Compose"
        }
    }
}
