//
//  CreateClass.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//

import Fluent

struct CreateClass: AsyncMigration {

    func prepare(on database: any Database) async throws {

        try await database.schema("classes")

            .id()

            .field("name", .string, .required)

            .field("capacity", .int, .required)

            .field(
                "coach_id",
                .uuid,
                .required,
                .references("coaches", "id", onDelete: .cascade)
            )

            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("classes").delete()
    }

}
