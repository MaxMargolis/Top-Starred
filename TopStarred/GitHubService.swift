//
//  GitHubService.swift
//  TopStarred
//
//  Created by Max Margolis on 4/26/21.
//

import Foundation
import Combine

enum NetworkError: LocalizedError {
	case nonHTTPResponse
	case statusCodeError(code: Int)
	case noData
}

class GitHubService {
	
	// MARK: Private Constants
	private let gitHubScheme = "https"
	private let gitHubHost = "api.github.com"
	private let authToken = "enter your auth token here"
	
	private typealias Contributor = String
	
	
	// MARK: Interface Functions
	
	/// Asynchronously provides the top 100 starred GitHub repositories and their top contributors
	/// - Returns: Publisher returns an array of `Repository` objects on success in descending order by number of stars. Network failures of retrieving repository data are propagated, while network failures of retrieving top contributor data are replaced with empty strings.
	func topRepositories() -> AnyPublisher<[Repository], Error> {
		let pub = topStarredRepositories()
			.flatMap { (gitHubRepositories) -> AnyPublisher<[Repository], Error> in
				
				let arrayOfRepositoryPublishers = gitHubRepositories.map { starRankedGitHubRepository -> AnyPublisher<Repository, Never> in
					
					self.topRepositoryContributor(for: starRankedGitHubRepository.repo.full_name)
						.replaceError(with: "") // We don't want the whole downstream publisher to fail if a contributor request goes awry
						.map { (contributor) -> Repository in
							
							Repository(starRank: starRankedGitHubRepository.starRank, url: URL(string: starRankedGitHubRepository.repo.html_url)!, fullName: starRankedGitHubRepository.repo.full_name, topContributor: contributor)
						}
						.eraseToAnyPublisher()
				}
				
				// Convert an array of publishers into a publisher of an array
				return Publishers.MergeMany(arrayOfRepositoryPublishers).collect()
					.sort {$0.starRank < $1.starRank}
					.setFailureType(to: Error.self) // We need to specify this because the upstream publishers for the contributors never fail with error
					.eraseToAnyPublisher()
			}
			.eraseToAnyPublisher()
		
		return pub
	}
	
	
	// MARK: Network Functions
	
	/// Asynchronously provides the top contributor for a GitHub repository
	/// - Parameter repositoryFullName: The "full name" of a GitHub repository. Ex: octocat/hello-world
	/// - Returns: Publisher of the top contributor's GitHub login handle on success, and an Error on failure.
	private func topRepositoryContributor(for repositoryFullName: String) -> AnyPublisher<Contributor, Error> {
		
		// Build the request based on https://docs.github.com/en/rest/reference/repos#list-repository-contributors
		
		let path = "/repos/\(repositoryFullName)/contributors" // returns contributors in descending order by number of commits
		let queryItems = [URLQueryItem(name: "per_page", value: "1")]
		var components = URLComponents()
		components.scheme = gitHubScheme
		components.host = gitHubHost
		components.path = path
		components.queryItems = queryItems
		let topContributorUrl = components.url!
		
		var request = URLRequest(url: topContributorUrl)
		request.setValue("token \(authToken)", forHTTPHeaderField: "Authorization")
		
		let pub = URLSession.shared.dataTaskPublisher(for: request)
			.tryMap { (data: Data, response: URLResponse) -> Data in
				
				guard let httpResponse = response as? HTTPURLResponse else {
					throw NetworkError.nonHTTPResponse
				}
				guard httpResponse.statusCode == 200 else {
					print("Response error. Code: \(httpResponse.statusCode).\n Response: \(httpResponse) ")
					throw NetworkError.statusCodeError(code: httpResponse.statusCode)
				}
				return data
			}
			.decode(type: [GitHubRepositoryContributor].self, decoder: JSONDecoder())
			.map {
				return $0.first?.login ?? "No Top Contributor Found"
			}
			.eraseToAnyPublisher()
		
		return pub
	}
	
	
	/// Asynchronously provides the top 100 starred repositories on GitHub in descending order by number of stars.
	/// - Returns: A publisher that returns an array of `IndexedGitHubRepository` objects on success, and an error on failure.
	private func topStarredRepositories() -> AnyPublisher<[StarRankedGitHubRepository], Error> {
		
		// Build the request based on https://docs.github.com/en/rest/reference/search
		
		let path = "/search/repositories"
		let queryItems = [URLQueryItem(name: "q", value: "stars:>0"),
						  URLQueryItem(name: "sort", value: "stars"),
						  URLQueryItem(name: "order", value: "desc"),
						  URLQueryItem(name: "per_page", value: "100")]
		var components = URLComponents()
		components.scheme = gitHubScheme
		components.host = gitHubHost
		components.path = path
		components.queryItems = queryItems
		let topRepositoriesUrl = components.url!
		
		var request = URLRequest(url: topRepositoriesUrl)
		request.setValue("token \(authToken)", forHTTPHeaderField: "Authorization")
		
		let pub = URLSession.shared.dataTaskPublisher(for: request)
			.tryMap { (data: Data, response: URLResponse) -> Data in
				
				guard let httpResponse = response as? HTTPURLResponse else {
					throw NetworkError.nonHTTPResponse
				}
				guard httpResponse.statusCode == 200 else {
					print("Response error. Code: \(httpResponse.statusCode).\n Response: \(httpResponse) ")
					throw NetworkError.statusCodeError(code: httpResponse.statusCode)
				}
				return data
			}
			.decode(type: GitHubRepositoriesSearchResult.self, decoder: JSONDecoder())
			.map { searchResult -> [StarRankedGitHubRepository] in
				print(searchResult.items.map {$0.full_name})
				return searchResult.items.enumerated().map {(index, result) in
					StarRankedGitHubRepository(starRank: index, repo: result)
				}
			}
			.eraseToAnyPublisher()
		
		return pub
	}
}

// MARK: GitHub Network Models

struct GitHubRepositoriesSearchResult: Codable {
	let items: [GitHubRepository]
}

struct GitHubRepository: Codable {
	/// The full name of the repository which is an amalgam of the owner's login handle and the name. Ex: octocat/hello-world
	let full_name: String
	/// The url for the website where the repository can be viewed. Ex: https://github.com/octocat/hello-world
	let html_url: String
}

struct GitHubRepositoryContributor: Codable {
	/// The GitHub login handle of the contributor
	let login: String
}


// MARK: Convenience Models

/// A GitHubRepository and it's rank with respect to number of stars (top is 0)
struct StarRankedGitHubRepository {
	/// Rank of the repository with respect to the number of stars (top is 0)
	let starRank: Int
	let repo: GitHubRepository
}


// MARK: Utility

// Created by John Sundell https://www.swiftbysundell.com/articles/connecting-and-merging-combine-publishers-in-swift/
extension Publisher where Output: Sequence {
	typealias Sorter = (Output.Element, Output.Element) -> Bool

	func sort(by sorter: @escaping Sorter) -> Publishers.Map<Self, [Output.Element]> {
		map { sequence in
			sequence.sorted(by: sorter)
		}
	}
}
