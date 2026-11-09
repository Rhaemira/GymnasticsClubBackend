//
//  CreateEnrollment.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//


import Fluent

struct CreateEnrollment: AsyncMigration {

    func prepare(
        on database: any Database
    ) async throws {

        try await database
            .schema("enrollments")

            .id()

            .field(
                "athlete_id",
                .uuid,
                .required,
                .references(
                    "athletes",
                    "id"
                )
            )

            .field(
                "class_id",
                .uuid,
                .required,
                .references(
                    "classes",
                    "id"
                )
            )

            .unique(
                on:
                "athlete_id",
                "class_id"
            )

            .create()
    }

    func revert(
        on database: any Database
    ) async throws {

        try await database
            .schema("enrollments")
            .delete()
    }
}
