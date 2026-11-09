//
//  CreateAttendance.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//

import Fluent

struct CreateAttendance: AsyncMigration {

    func prepare(on database: any Database) async throws {

        try await database.schema("attendance")

            .id()

            .field(
                "athlete_id",
                .uuid,
                .required,
                .references("athletes", "id", onDelete: .cascade)
            )

            .field(
                "class_id",
                .uuid,
                .required,
                .references("classes", "id", onDelete: .cascade)
            )

            .field(
                "attended_on",
                .datetime,
                .required
            )

            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("attendance").delete()
    }

}
