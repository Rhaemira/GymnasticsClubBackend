//
//  FixCascadeDeletes.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 7/19/26.
//

import Fluent

struct FixCascadeDeletes: AsyncMigration {

    func prepare(on database: any Database) async throws {

        // Drop in reverse dependency order
        try await database.schema("attendance").delete()
        try await database.schema("enrollments").delete()
        try await database.schema("classes").delete()

        // Recreate classes with CASCADE on coach_id
        try await database.schema("classes")
            .id()
            .field("name", .string, .required)
            .field("capacity", .int, .required)
            .field(
                "coach_id", .uuid, .required,
                .references("coaches", "id", onDelete: .cascade)
            )
            .create()

        // Recreate enrollments with CASCADE on both FKs
        try await database.schema("enrollments")
            .id()
            .field(
                "athlete_id", .uuid, .required,
                .references("athletes", "id", onDelete: .cascade)
            )
            .field(
                "class_id", .uuid, .required,
                .references("classes", "id", onDelete: .cascade)
            )
            .unique(on: "athlete_id", "class_id")
            .create()

        // Recreate attendance with CASCADE on both FKs
        try await database.schema("attendance")
            .id()
            .field(
                "athlete_id", .uuid, .required,
                .references("athletes", "id", onDelete: .cascade)
            )
            .field(
                "class_id", .uuid, .required,
                .references("classes", "id", onDelete: .cascade)
            )
            .field("attended_on", .datetime, .required)
            .create()

    }

    func revert(on database: any Database) async throws {
        try await database.schema("attendance").delete()
        try await database.schema("enrollments").delete()
        try await database.schema("classes").delete()
    }

}
