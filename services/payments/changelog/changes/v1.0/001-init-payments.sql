--liquibase formatted sql

--changeset payments-dev:001-create-payments labels:v1.0 context:all
CREATE TABLE payments (
    id             BIGINT         NOT NULL AUTO_INCREMENT,
    order_id       BIGINT         NOT NULL,
    amount         DECIMAL(15, 2) NOT NULL,
    method         VARCHAR(50)    NOT NULL,
    status         VARCHAR(30)    NOT NULL DEFAULT 'pending',
    ref_number     VARCHAR(100)   NULL,
    paid_at        TIMESTAMP      NULL,
    created_at     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_payments PRIMARY KEY (id)
);
--rollback DROP TABLE IF EXISTS payments;

--changeset payments-dev:002-create-payment-logs labels:v1.0 context:all
CREATE TABLE payment_logs (
    id          BIGINT      NOT NULL AUTO_INCREMENT,
    payment_id  BIGINT      NOT NULL,
    event       VARCHAR(50) NOT NULL,
    payload     JSON        NULL,
    created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_payment_logs            PRIMARY KEY (id),
    CONSTRAINT fk_payment_logs_payment_id FOREIGN KEY (payment_id) REFERENCES payments (id) ON DELETE CASCADE
);
--rollback DROP TABLE IF EXISTS payment_logs;

--changeset payments-dev:003-idx-payments-order labels:v1.0 context:all
CREATE INDEX idx_payments_order_id ON payments (order_id);
--rollback DROP INDEX idx_payments_order_id ON payments;
