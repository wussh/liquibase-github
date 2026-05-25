--liquibase formatted sql

--changeset dev:001-create-users
CREATE TABLE users (
    id       BIGINT      NOT NULL AUTO_INCREMENT,
    username VARCHAR(100) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    CONSTRAINT pk_users         PRIMARY KEY (id),
    CONSTRAINT uq_users_email   UNIQUE (email)
);
--rollback DROP TABLE IF EXISTS users;
