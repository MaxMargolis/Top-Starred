//
//  TopStarredListViewModel.swift
//  TopStarred
//
//  Created by Max Margolis on 4/26/21.
//

import Foundation
import Combine

/// Necessary data for displaying information about a GitHub Repository in a `TopStarredListView`
struct Repository {
	let starRank: Int
	let url: URL
	let fullName: String
	let topContributor: String
}

class TopStarredListViewModel: ObservableObject {
	
	// MARK: Dependencies
	let gitHubService: GitHubService
	
	// MARK: Published Interface Variables
	@Published var repositories = [Repository]()
	@Published var showNetworkError = false
	@Published var showProgressIndicator = true
	
	// MARK: Private Variables
	private var cancellables : Set<AnyCancellable> = []
	
	// MARK: Lifecycle
	init(gitHubService: GitHubService) {
		self.gitHubService = gitHubService
		
		self.gitHubService.topRepositories()
			.subscribe(on: DispatchQueue.global())
			.receive(on: DispatchQueue.main)
			.sink { (completion) in
				switch completion {
				case .finished:
					self.showProgressIndicator = false
				case .failure(let error):
					print("Network error: \(error)")
					self.showNetworkError = true
				}
			} receiveValue: { (repositories) in
				self.repositories = repositories
			}
			.store(in: &cancellables)

	}
}
