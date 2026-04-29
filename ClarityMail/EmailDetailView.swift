//
//  EmailDetailView.swift
//  ClarityMail
//
//  Created by Sukhman Singh on 4/29/26.
//

import SwiftUI

struct EmailDetailView: View {
    let email: Email

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(email.subject)
                        .font(.title2.bold())

                    Text(email.sender)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("AI Summary", systemImage: "sparkles")
                        .font(.headline)

                    Text("AI summary will appear here after the OpenAI backend route is connected.")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(email.snippet)
                    .font(.body)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding()
        }
        .navigationTitle(email.subject)
    }
}
