--liquibase formatted sql

--changeset users-dev:001-create-users labels:v1.0 context:all
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(100) NOT NULL,
    email      VARCHAR(255) NULL,
    phone      VARCHAR(20)  NULL,
    status     VARCHAR(20)  NOT NULL DEFAULT 'active',
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_users          PRIMARY KEY (id),
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_email    UNIQUE (email)
);
--rollback DROP TABLE IF EXISTS users;

--changeset users-dev:002-create-user-roles labels:v1.0 context:all
CREATE TABLE user_roles (
    id      BIGINT      NOT NULL AUTO_INCREMENT,
    user_id BIGINT      NOT NULL,
    role    VARCHAR(50) NOT NULL DEFAULT 'customer',
    CONSTRAINT pk_user_roles         PRIMARY KEY (id),
    CONSTRAINT fk_user_roles_user_id FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
--rollback DROP TABLE IF EXISTS user_roles;
