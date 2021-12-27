//
//  TopStarredListView.swift
//  TopStarred
//
//  Created by Max Margolis on 4/26/21.
//

import SwiftUI

struct TopStarredListView: View {

	@StateObject var model = TopStarredListViewModel(gitHubService: GitHubService())
	
    var body: some View {
		ZStack {
			List(model.repositories, id: \.url) {repo in
				VStack(alignment: .leading) {
					Text(repo.fullName)
						.font(.system(.headline))
						.background(Color.yellow)
					Text(repo.topContributor)
						.font(.system(.subheadline))
				}
			}
			.alert(isPresented: $model.showNetworkError) {
				Alert(title: Text("Oops! We're having some technical difficulties, please try again later."))
			}
			
			if model.showProgressIndicator {
				VStack(alignment:.center) {
					Image("github-star")
						.resizable()
						.frame(width: 60, height: 60)
					ProgressView()
					Text("Loading")
						.font(.system(.caption))
						.foregroundColor(.yellow)
						.padding(.vertical)
				}
			}
			
			
		}
    }
}


