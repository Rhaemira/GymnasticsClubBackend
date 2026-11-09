//
//  CreateAthlete.swift
//  GymnasticsClubBackend
//
//  Created by Amirali Yazdani on 6/14/26.
//


import Fluent

struct CreateAthlete: AsyncMigration {

    func prepare(on database: any Database) async throws {

        try await database.schema("athletes")

            .id()

            .field(
                "full_name",
                .string,
                .required
            )

            .field(
                "age",
                .int,
                .required
            )

            .field(
                "level",
                .string,
                .required
            )

            .create()
    }

    func revert(
        on database: any Database
    ) async throws {

        try await database
            .schema("athletes")
            .delete()
    }
}
