    -- ============================================================
    -- Healthcare Billing & Transaction Management System
    -- ============================================================


    -- ============================================================
    -- 1. CORE TABLES
    -- ============================================================


    -- ============================================================
    -- Table: patients
    -- ============================================================

    CREATE SCHEMA healthcare_billing;

    CREATE TABLE healthcare_billing.patients (
        patient_id INTEGER PRIMARY KEY,
        full_name VARCHAR(100) NOT NULL,
        email VARCHAR(100) NOT NULL UNIQUE,
        phone_number VARCHAR(20),
        date_of_birth DATE,
        created_at TIMESTAMP NOT NULL
    );


    -- ============================================================
    -- Table: billing_accounts
    -- ============================================================

    CREATE TABLE healthcare_billing.billing_accounts (
        account_id INTEGER PRIMARY KEY,
        patient_id INTEGER NOT NULL,
        account_number VARCHAR(30) NOT NULL UNIQUE,
        account_type VARCHAR(20) NOT NULL,
        current_balance DECIMAL(15,2) NOT NULL,
        account_status VARCHAR(20) NOT NULL,
        created_at TIMESTAMP NOT NULL,
        updated_at TIMESTAMP NOT NULL,

        CONSTRAINT fk_billing_accounts_patient
            FOREIGN KEY (patient_id)
            REFERENCES healthcare_billing.patients(patient_id),

        CONSTRAINT chk_billing_balance_non_negative
            CHECK (current_balance >= 0),

        CONSTRAINT chk_billing_account_type
            CHECK (account_type IN ('PATIENT', 'INSURANCE', 'HOSPITAL')),

        CONSTRAINT chk_billing_account_status
            CHECK (account_status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED', 'CLOSED'))
    );


    -- ============================================================
    -- Table: billing_fee_rules
    -- ============================================================

    CREATE TABLE healthcare_billing.billing_fee_rules (
        fee_rule_id INTEGER PRIMARY KEY,
        transaction_type VARCHAR(30) NOT NULL,
        minimum_amount DECIMAL(15,2) NOT NULL,
        maximum_amount DECIMAL(15,2) NOT NULL,
        fee_type VARCHAR(20) NOT NULL,
        fee_value DECIMAL(15,2) NOT NULL,
        is_active CHAR(1) NOT NULL,

        CONSTRAINT chk_billing_fee_type
            CHECK (fee_type IN ('PERCENTAGE', 'FIXED')),

        CONSTRAINT chk_billing_fee_active
            CHECK (is_active IN ('Y', 'N')),

        CONSTRAINT chk_billing_amount_range
            CHECK (
                minimum_amount >= 0
                AND maximum_amount >= minimum_amount
            ),

        CONSTRAINT chk_billing_fee_value
            CHECK (fee_value >= 0)
    );


    -
-- ============================================================
-- Table: healthcare_transactions
--
-- Grain:
-- One row represents one healthcare billing transaction
-- between two billing accounts.
-- ============================================================

CREATE TABLE healthcare_billing.healthcare_transactions (
    transaction_id INTEGER PRIMARY KEY,
    transaction_reference VARCHAR(50) NOT NULL UNIQUE,
    payer_account_id INTEGER NOT NULL,
    receiver_account_id INTEGER NOT NULL,
    transaction_type VARCHAR(30) NOT NULL,
    payment_amount DECIMAL(15,2) NOT NULL,
    fee_amount DECIMAL(15,2) NOT NULL,
    total_debit_amount DECIMAL(15,2) NOT NULL,
    transaction_status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,

    fee_rule_id INTEGER,

    CONSTRAINT fk_healthcare_tx_fee_rule
        FOREIGN KEY (fee_rule_id)
        REFERENCES healthcare_billing.billing_fee_rules(fee_rule_id),

    CONSTRAINT fk_healthcare_tx_payer
        FOREIGN KEY (payer_account_id)
        REFERENCES healthcare_billing.billing_accounts(account_id),

    CONSTRAINT fk_healthcare_tx_receiver
        FOREIGN KEY (receiver_account_id)
        REFERENCES healthcare_billing.billing_accounts(account_id),

    CONSTRAINT chk_healthcare_payment_positive
        CHECK (payment_amount > 0),

    CONSTRAINT chk_healthcare_fee_non_negative
        CHECK (fee_amount >= 0),

    CONSTRAINT chk_healthcare_total_debit
        CHECK (total_debit_amount >= payment_amount),

    CONSTRAINT chk_healthcare_different_accounts
        CHECK (payer_account_id <> receiver_account_id),

    CONSTRAINT chk_healthcare_tx_status
        CHECK (
            transaction_status IN (
                'COMPLETED',
                'FAILED',
                'PENDING',
                'REVERSED'
            )
        )
);


    -- ============================================================
    -- Table: account_balance_audit
    --
    -- Grain:
    -- One row represents one balance change recorded for a
    -- healthcare billing account.
    -- ============================================================

    CREATE TABLE healthcare_billing.account_balance_audit (
        audit_id INTEGER PRIMARY KEY,
        account_id INTEGER NOT NULL,
        transaction_id INTEGER,
        balance_before DECIMAL(15,2) NOT NULL,
        debit_amount DECIMAL(15,2) NOT NULL,
        credit_amount DECIMAL(15,2) NOT NULL,
        balance_after DECIMAL(15,2) NOT NULL,
        action_type VARCHAR(20) NOT NULL,
        created_at TIMESTAMP NOT NULL,

        CONSTRAINT fk_balance_audit_account
            FOREIGN KEY (account_id)
            REFERENCES healthcare_billing.billing_accounts(account_id),

        CONSTRAINT fk_balance_audit_transaction
            FOREIGN KEY (transaction_id)
            REFERENCES healthcare_billing.healthcare_transactions(transaction_id),

        CONSTRAINT chk_balance_audit_debit
            CHECK (debit_amount >= 0),

        CONSTRAINT chk_balance_audit_credit
            CHECK (credit_amount >= 0),

        CONSTRAINT chk_balance_audit_after
            CHECK (balance_after >= 0),

        CONSTRAINT chk_balance_audit_action
            CHECK (action_type IN ('DEBIT', 'CREDIT', 'ADJUSTMENT'))
    );


    -- ============================================================
    -- Table: failed_transactions
    --
    -- Grain:
    -- One row represents one healthcare billing transaction
    -- attempt that failed validation.
    -- ============================================================

    CREATE TABLE healthcare_billing.failed_transactions (
        failed_transaction_id INTEGER PRIMARY KEY,
        payer_account_id INTEGER,
        receiver_account_id INTEGER,
        payment_amount DECIMAL(15,2),
        failure_reason VARCHAR(200) NOT NULL,
        failed_at TIMESTAMP NOT NULL,

        CONSTRAINT fk_failed_tx_payer
            FOREIGN KEY (payer_account_id)
            REFERENCES healthcare_billing.billing_accounts(account_id),

        CONSTRAINT fk_failed_tx_receiver
            FOREIGN KEY (receiver_account_id)
            REFERENCES healthcare_billing.billing_accounts(account_id),

        CONSTRAINT chk_failed_payment_positive
            CHECK (
                payment_amount IS NULL
                OR payment_amount > 0
            )
    );


-- ============================================================
-- 2. INDEXES
-- ============================================================


-- Frequently used patient lookup

CREATE INDEX idx_billing_accounts_patient
ON healthcare_billing.billing_accounts(patient_id);


-- Account status filtering

CREATE INDEX idx_billing_accounts_status
ON healthcare_billing.billing_accounts(account_status);


-- Healthcare transaction payer analysis

CREATE INDEX idx_healthcare_tx_payer
ON healthcare_billing.healthcare_transactions(payer_account_id);


-- Healthcare transaction receiver analysis

CREATE INDEX idx_healthcare_tx_receiver
ON healthcare_billing.healthcare_transactions(receiver_account_id);


-- Transaction status filtering

CREATE INDEX idx_healthcare_tx_status
ON healthcare_billing.healthcare_transactions(transaction_status);


-- Transaction type and status analysis

CREATE INDEX idx_healthcare_tx_type_status
ON healthcare_billing.healthcare_transactions(
    transaction_type,
    transaction_status
);


-- Audit trail analysis by account

CREATE INDEX idx_balance_audit_account
ON healthcare_billing.account_balance_audit(account_id);


-- Audit trail analysis by transaction

CREATE INDEX idx_balance_audit_transaction
ON healthcare_billing.account_balance_audit(transaction_id);


-- Fee rule lookup

CREATE INDEX idx_billing_fee_type_active
ON healthcare_billing.billing_fee_rules(
    transaction_type,
    is_active
);


-- ============================================================
-- 3. SAMPLE DATA
-- ============================================================


-- ============================================================
-- Sample data: patients
-- ============================================================

INSERT INTO healthcare_billing.patients (
    patient_id,
    full_name,
    email,
    phone_number,
    date_of_birth,
    created_at
)
VALUES
(1, 'Ahmed Hassan', 'ahmed.hassan@email.com', '+20-100-000-1001',
 DATE '1998-04-15', TIMESTAMP '2024-01-10 09:00:00'),

(2, 'Mariam Ali', 'mariam.ali@email.com', '+20-100-000-1002',
 DATE '1995-08-22', TIMESTAMP '2024-01-12 10:30:00'),

(3, 'Omar Mohamed', 'omar.mohamed@email.com', '+20-100-000-1003',
 DATE '2001-02-10', TIMESTAMP '2024-01-15 14:00:00'),

(4, 'Nour Ahmed', 'nour.ahmed@email.com', '+20-100-000-1004',
 DATE '1992-11-05', TIMESTAMP '2024-02-01 11:00:00'),

(5, 'Youssef Mahmoud', 'youssef.mahmoud@email.com', '+20-100-000-1005',
 DATE '1989-06-18', TIMESTAMP '2024-02-05 16:45:00'),

(6, 'Salma Ibrahim', 'salma.ibrahim@email.com', '+20-100-000-1006',
 DATE '1999-12-27', TIMESTAMP '2024-02-10 08:20:00');


-- ============================================================
-- Sample data: billing accounts
--
-- Different balances and statuses are intentionally included
-- to test successful and failed healthcare transactions.
-- ============================================================

INSERT INTO healthcare_billing.billing_accounts (
    account_id,
    patient_id,
    account_number,
    account_type,
    current_balance,
    account_status,
    created_at,
    updated_at
)
VALUES
(101, 1, 'PAT-1001001', 'PATIENT', 5000.00, 'ACTIVE',
 TIMESTAMP '2024-01-10 09:05:00',
 TIMESTAMP '2024-01-10 09:05:00'),

(102, 1, 'PAT-1001002', 'PATIENT', 12000.00, 'ACTIVE',
 TIMESTAMP '2024-01-10 09:10:00',
 TIMESTAMP '2024-01-10 09:10:00'),

(201, 2, 'PAT-2002001', 'PATIENT', 2500.00, 'ACTIVE',
 TIMESTAMP '2024-01-12 10:35:00',
 TIMESTAMP '2024-01-12 10:35:00'),

(202, 2, 'PAT-2002002', 'PATIENT', 800.00, 'INACTIVE',
 TIMESTAMP '2024-01-12 10:40:00',
 TIMESTAMP '2024-01-12 10:40:00'),

(301, 3, 'PAT-3003001', 'PATIENT', 7500.00, 'ACTIVE',
 TIMESTAMP '2024-01-15 14:05:00',
 TIMESTAMP '2024-01-15 14:05:00'),

(401, 4, 'PAT-4004001', 'PATIENT', 150.00, 'ACTIVE',
 TIMESTAMP '2024-02-01 11:05:00',
 TIMESTAMP '2024-02-01 11:05:00'),

(501, 5, 'PAT-5005001', 'PATIENT', 3000.00, 'ACTIVE',
 TIMESTAMP '2024-02-05 16:50:00',
 TIMESTAMP '2024-02-05 16:50:00'),

(601, 6, 'PAT-6006001', 'PATIENT', 10000.00, 'ACTIVE',
 TIMESTAMP '2024-02-10 08:25:00',
 TIMESTAMP '2024-02-10 08:25:00');


-- ============================================================
-- Sample data: billing fee rules
--
-- Active rules are used to calculate healthcare transaction
-- fees according to transaction type and payment amount.
-- ============================================================

INSERT INTO healthcare_billing.billing_fee_rules (
    fee_rule_id,
    transaction_type,
    minimum_amount,
    maximum_amount,
    fee_type,
    fee_value,
    is_active
)
VALUES
(1, 'CONSULTATION', 0.01, 1000.00,
 'FIXED', 2.50, 'Y'),

(2, 'CONSULTATION', 1000.01, 5000.00,
 'PERCENTAGE', 0.50, 'Y'),

(3, 'CONSULTATION', 5000.01, 999999.99,
 'PERCENTAGE', 0.25, 'Y'),

(4, 'LABORATORY', 0.01, 999999.99,
 'FIXED', 1.00, 'Y'),

(5, 'RADIOLOGY', 0.01, 999999.99,
 'PERCENTAGE', 1.00, 'N');


-- ============================================================
-- 4. ACID TRANSACTION TEST CASES
-- ============================================================


-- ============================================================
-- TEST CASE 1: Successful healthcare payment
--
-- Payment:
-- 2000.00 from account 101 to account 301
--
-- Transaction type:
-- CONSULTATION
--
-- Applicable rule:
-- fee_rule_id 2
--
-- Fee:
-- 0.50% of 2000.00 = 10.00
--
-- Total debit:
-- 2010.00
--
-- Expected:
-- Account 101: 5000.00 -> 2990.00
-- Account 301: 7500.00 -> 9500.00
-- ============================================================

BEGIN TRANSACTION;


-- Validate payer account

SELECT
    account_id,
    current_balance,
    account_status
FROM healthcare_billing.billing_accounts
WHERE account_id = 101;


-- Validate receiver account

SELECT
    account_id,
    current_balance,
    account_status
FROM healthcare_billing.billing_accounts
WHERE account_id = 301;


-- Find applicable fee rule

SELECT
    fee_rule_id,
    transaction_type,
    fee_type,
    fee_value
FROM healthcare_billing.billing_fee_rules
WHERE transaction_type = 'CONSULTATION'
  AND minimum_amount <= 2000.00
  AND maximum_amount >= 2000.00
  AND is_active = 'Y';


-- Insert completed healthcare transaction

INSERT INTO healthcare_billing.healthcare_transactions (
    transaction_id,
    transaction_reference,
    payer_account_id,
    receiver_account_id,
    transaction_type,
    payment_amount,
    fee_amount,
    total_debit_amount,
    transaction_status,
    created_at,
    completed_at
)
VALUES (
    1001,
    'HTX-20260915-0001',
    101,
    301,
    'CONSULTATION',
    2000.00,
    10.00,
    2010.00,
    'COMPLETED',
    TIMESTAMP '2026-09-15 10:00:00',
    TIMESTAMP '2026-09-15 10:00:01'
);


-- Debit payer account

UPDATE healthcare_billing.billing_accounts
SET
    current_balance = current_balance - 2010.00,
    updated_at = TIMESTAMP '2026-09-15 10:00:01'
WHERE account_id = 101
  AND current_balance >= 2010.00
  AND account_status = 'ACTIVE';


-- Credit receiver account

UPDATE healthcare_billing.billing_accounts
SET
    current_balance = current_balance + 2000.00,
    updated_at = TIMESTAMP '2026-09-15 10:00:01'
WHERE account_id = 301
  AND account_status = 'ACTIVE';


-- Audit trail: payer debit

INSERT INTO healthcare_billing.account_balance_audit (
    audit_id,
    account_id,
    transaction_id,
    balance_before,
    debit_amount,
    credit_amount,
    balance_after,
    action_type,
    created_at
)
VALUES (
    1,
    101,
    1001,
    5000.00,
    2010.00,
    0.00,
    2990.00,
    'DEBIT',
    TIMESTAMP '2026-09-15 10:00:01'
);


-- Audit trail: receiver credit

INSERT INTO healthcare_billing.account_balance_audit (
    audit_id,
    account_id,
    transaction_id,
    balance_before,
    debit_amount,
    credit_amount,
    balance_after,
    action_type,
    created_at
)
VALUES (
    2,
    301,
    1001,
    7500.00,
    0.00,
    2000.00,
    9500.00,
    'CREDIT',
    TIMESTAMP '2026-09-15 10:00:01'
);


-- Commit only after all operations succeed

COMMIT;


-- ============================================================
-- TEST CASE 2: Successful healthcare payment with FIXED fee
--
-- Payment:
-- 500.00 from account 301 to account 501
--
-- Applicable rule:
-- fee_rule_id 1
--
-- Fee:
-- 2.50
--
-- Total debit:
-- 502.50
--
-- Expected:
-- Account 301: 9500.00 -> 8997.50
-- Account 501: 3000.00 -> 3500.00
-- ============================================================

BEGIN TRANSACTION;


-- Validate payer and receiver accounts

SELECT
    account_id,
    current_balance,
    account_status
FROM healthcare_billing.billing_accounts
WHERE account_id IN (301, 501)
ORDER BY account_id;


-- Find applicable fee rule

SELECT
    fee_rule_id,
    transaction_type,
    fee_type,
    fee_value
FROM healthcare_billing.billing_fee_rules
WHERE transaction_type = 'CONSULTATION'
  AND minimum_amount <= 500.00
  AND maximum_amount >= 500.00
  AND is_active = 'Y';


-- Insert completed healthcare transaction

INSERT INTO healthcare_billing.healthcare_transactions (
    transaction_id,
    transaction_reference,
    payer_account_id,
    receiver_account_id,
    transaction_type,
    payment_amount,
    fee_amount,
    total_debit_amount,
    transaction_status,
    created_at,
    completed_at
)
VALUES (
    1002,
    'HTX-20260915-0002',
    301,
    501,
    'CONSULTATION',
    500.00,
    2.50,
    502.50,
    'COMPLETED',
    TIMESTAMP '2026-09-15 11:00:00',
    TIMESTAMP '2026-09-15 11:00:01'
);


-- Debit payer account

UPDATE healthcare_billing.billing_accounts
SET
    current_balance = current_balance - 502.50,
    updated_at = TIMESTAMP '2026-09-15 11:00:01'
WHERE account_id = 301
  AND current_balance >= 502.50
  AND account_status = 'ACTIVE';


-- Credit receiver account

UPDATE healthcare_billing.billing_accounts
SET
    current_balance = current_balance + 500.00,
    updated_at = TIMESTAMP '2026-09-15 11:00:01'
WHERE account_id = 501
  AND account_status = 'ACTIVE';


-- Audit trail: payer debit

INSERT INTO healthcare_billing.account_balance_audit (
    audit_id,
    account_id,
    transaction_id,
    balance_before,
    debit_amount,
    credit_amount,
    balance_after,
    action_type,
    created_at
)
VALUES (
    3,
    301,
    1002,
    9500.00,
    502.50,
    0.00,
    8997.50,
    'DEBIT',
    TIMESTAMP '2026-09-15 11:00:01'
);


-- Audit trail: receiver credit

INSERT INTO healthcare_billing.account_balance_audit (
    audit_id,
    account_id,
    transaction_id,
    balance_before,
    debit_amount,
    credit_amount,
    balance_after,
    action_type,
    created_at
)
VALUES (
    4,
    501,
    1002,
    3000.00,
    0.00,
    500.00,
    3500.00,
    'CREDIT',
    TIMESTAMP '2026-09-15 11:00:01'
);


-- Commit transaction

COMMIT;


-- ============================================================
-- TEST CASE 3: Failed healthcare payment
--
-- Reason:
-- Insufficient balance
--
-- Attempt:
-- 200.00 from account 401
--
-- Current balance:
-- 150.00
--
-- Expected:
-- Transaction is rolled back.
-- No balance is changed.
-- Failure is recorded after rollback.
-- ============================================================

BEGIN TRANSACTION;


-- Validate payer account

SELECT
    account_id,
    current_balance,
    account_status
FROM healthcare_billing.billing_accounts
WHERE account_id = 401;


-- Validation result:
-- Current balance = 150.00
-- Required payment = 200.00 + applicable fee
-- Validation fails.


ROLLBACK;


-- Record failed transaction separately.
-- This record is intentionally inserted after ROLLBACK
-- so that the failure log is preserved.

INSERT INTO healthcare_billing.failed_transactions (
    failed_transaction_id,
    payer_account_id,
    receiver_account_id,
    payment_amount,
    failure_reason,
    failed_at
)
VALUES (
    1,
    401,
    201,
    200.00,
    'Insufficient balance to cover payment amount plus fee',
    TIMESTAMP '2026-09-15 12:00:00'
);

COMMIT;


-- ============================================================
-- TEST CASE 4: Failed healthcare payment
--
-- Reason:
-- Payer and receiver are the same account.
--
-- Expected:
-- Transaction is rejected.
-- No balance change occurs.
-- Failure is recorded.
-- ============================================================

BEGIN TRANSACTION;


-- Validation logic

SELECT
    account_id,
    account_status,
    current_balance
FROM healthcare_billing.billing_accounts
WHERE account_id = 101;


-- Validation result:
-- payer_account_id = receiver_account_id
-- Transaction is not allowed.

ROLLBACK;


-- Record failure after rollback

INSERT INTO healthcare_billing.failed_transactions (
    failed_transaction_id,
    payer_account_id,
    receiver_account_id,
    payment_amount,
    failure_reason,
    failed_at
)
VALUES (
    2,
    101,
    101,
    100.00,
    'Payer and receiver billing accounts cannot be the same',
    TIMESTAMP '2026-09-15 12:05:00'
);

COMMIT;


-- ============================================================
-- TEST CASE 5: Failed healthcare payment
--
-- Reason:
-- Receiver account is INACTIVE.
--
-- Attempt:
-- 100.00 from account 201 to account 202
--
-- Expected:
-- Transaction is rejected.
-- No balance change occurs.
-- Failure is recorded.
-- ============================================================

BEGIN TRANSACTION;


-- Validate payer and receiver accounts

SELECT
    account_id,
    current_balance,
    account_status
FROM healthcare_billing.billing_accounts
WHERE account_id IN (201, 202)
ORDER BY account_id;


-- Validation result:
-- Account 202 is INACTIVE.
-- Transaction cannot be completed.

ROLLBACK;


-- Record failure after rollback

INSERT INTO healthcare_billing.failed_transactions (
    failed_transaction_id,
    payer_account_id,
    receiver_account_id,
    payment_amount,
    failure_reason,
    failed_at
)
VALUES (
    3,
    201,
    202,
    100.00,
    'Receiver billing account is not ACTIVE',
    TIMESTAMP '2026-09-15 12:10:00'
);

COMMIT;


-- ============================================================
-- 5. TRANSACTION VERIFICATION QUERIES
-- ============================================================


-- ============================================================
-- Query 1: All billing accounts and current balances
-- ============================================================

SELECT
    a.account_id,
    a.account_number,
    p.full_name AS patient_name,
    a.account_type,
    a.current_balance,
    a.account_status,
    a.updated_at
FROM healthcare_billing.billing_accounts a
JOIN healthcare_billing.patients p
    ON a.patient_id = p.patient_id
ORDER BY a.account_id;


-- ============================================================
-- Query 2: All completed healthcare transactions
-- ============================================================

SELECT
    transaction_id,
    transaction_reference,
    payer_account_id,
    receiver_account_id,
    transaction_type,
    payment_amount,
    fee_amount,
    total_debit_amount,
    transaction_status,
    created_at,
    completed_at
FROM healthcare_billing.healthcare_transactions
WHERE transaction_status = 'COMPLETED'
ORDER BY transaction_id;


-- ============================================================
-- Query 3: Healthcare transaction history
-- for a selected billing account
-- ============================================================

SELECT
    t.transaction_id,
    t.transaction_reference,
    t.payer_account_id,
    t.receiver_account_id,
    t.transaction_type,
    t.payment_amount,
    t.fee_amount,
    t.total_debit_amount,
    t.transaction_status,
    t.completed_at,

    CASE
        WHEN t.payer_account_id = 101 THEN 'OUTGOING'
        WHEN t.receiver_account_id = 101 THEN 'INCOMING'
    END AS transaction_direction

FROM healthcare_billing.healthcare_transactions t

WHERE t.payer_account_id = 101
   OR t.receiver_account_id = 101

ORDER BY t.completed_at;


-- ============================================================
-- Query 4: Audit trail for a selected transaction
-- ============================================================

SELECT
    audit_id,
    account_id,
    transaction_id,
    balance_before,
    debit_amount,
    credit_amount,
    balance_after,
    action_type,
    created_at
FROM healthcare_billing.account_balance_audit
WHERE transaction_id = 1001
ORDER BY audit_id;


-- ============================================================
-- Query 5: Failed healthcare transactions
-- ============================================================

SELECT
    failed_transaction_id,
    payer_account_id,
    receiver_account_id,
    payment_amount,
    failure_reason,
    failed_at
FROM healthcare_billing.failed_transactions
ORDER BY failed_transaction_id;


-- ============================================================
-- Query 6: Total fees collected by healthcare transaction type
-- ============================================================

SELECT
    transaction_type,
    COUNT(*) AS transaction_count,
    SUM(fee_amount) AS total_fees_collected,
    SUM(payment_amount) AS total_payment_amount
FROM healthcare_billing.healthcare_transactions
WHERE transaction_status = 'COMPLETED'
GROUP BY transaction_type
ORDER BY transaction_type;


-- ============================================================
-- Query 7: Patient-level healthcare payment summary
-- ============================================================

SELECT
    p.patient_id,
    p.full_name AS patient_name,
    COUNT(t.transaction_id) AS completed_transactions,
    SUM(t.payment_amount) AS total_healthcare_payments,
    SUM(t.fee_amount) AS total_fees
FROM healthcare_billing.patients p
JOIN healthcare_billing.billing_accounts a
    ON p.patient_id = a.patient_id
JOIN healthcare_billing.healthcare_transactions t
    ON a.account_id = t.payer_account_id
WHERE t.transaction_status = 'COMPLETED'
GROUP BY
    p.patient_id,
    p.full_name
ORDER BY total_healthcare_payments DESC;


-- ============================================================
-- Query 8: Healthcare transactions by status
-- ============================================================

SELECT
    transaction_status,
    COUNT(*) AS transaction_count,
    SUM(payment_amount) AS total_payment_amount,
    SUM(fee_amount) AS total_fee_amount
FROM healthcare_billing.healthcare_transactions
GROUP BY transaction_status
ORDER BY transaction_status;


-- ============================================================
-- Query 9: Billing accounts with low available balance
-- ============================================================

SELECT
    account_id,
    account_number,
    account_type,
    current_balance,
    account_status
FROM healthcare_billing.billing_accounts
WHERE current_balance < 1000.00
ORDER BY current_balance;


-- ============================================================
-- Query 10: Balance audit verification
--
-- The audit records should represent the account balance
-- transitions caused by completed transactions.
-- ============================================================

SELECT
    account_id,
    COUNT(*) AS audit_event_count,
    SUM(debit_amount) AS total_debits,
    SUM(credit_amount) AS total_credits
FROM healthcare_billing.account_balance_audit
GROUP BY account_id
ORDER BY account_id;


-- ============================================================
-- Query 11: Failed transaction analysis
-- ============================================================

SELECT
    failure_reason,
    COUNT(*) AS failure_count,
    SUM(payment_amount) AS total_attempted_payment
FROM healthcare_billing.failed_transactions
GROUP BY failure_reason
ORDER BY failure_count DESC;


-- ============================================================
-- Query 12: Payment volume by transaction type
-- ============================================================

SELECT
    transaction_type,
    COUNT(*) AS transaction_count,
    SUM(payment_amount) AS total_payment_amount,
    AVG(payment_amount) AS average_payment_amount,
    MAX(payment_amount) AS maximum_payment_amount,
    MIN(payment_amount) AS minimum_payment_amount
FROM healthcare_billing.healthcare_transactions
WHERE transaction_status = 'COMPLETED'
GROUP BY transaction_type
ORDER BY total_payment_amount DESC;


-- ============================================================
-- Query 13: Current balance by patient
-- ============================================================

SELECT
    p.patient_id,
    p.full_name AS patient_name,
    SUM(a.current_balance) AS total_current_balance
FROM healthcare_billing.patients p
JOIN healthcare_billing.billing_accounts a
    ON p.patient_id = a.patient_id
GROUP BY
    p.patient_id,
    p.full_name
ORDER BY total_current_balance DESC;


-- ============================================================
-- Query 14: Completed transactions with patient names
-- ============================================================

SELECT
    t.transaction_id,
    t.transaction_reference,

    payer.full_name AS payer_name,
    receiver.full_name AS receiver_name,

    t.transaction_type,
    t.payment_amount,
    t.fee_amount,
    t.total_debit_amount,
    t.completed_at

FROM healthcare_billing.healthcare_transactions t

JOIN healthcare_billing.billing_accounts payer_account
    ON t.payer_account_id = payer_account.account_id

JOIN healthcare_billing.patients payer
    ON payer_account.patient_id = payer.patient_id

JOIN healthcare_billing.billing_accounts receiver_account
    ON t.receiver_account_id = receiver_account.account_id

JOIN healthcare_billing.patients receiver
    ON receiver_account.patient_id = receiver.patient_id

WHERE t.transaction_status = 'COMPLETED'

ORDER BY t.completed_at;


-- ============================================================
-- Query 15: Financial consistency check
--
-- The total balance reduction caused by completed payments
-- should equal the total healthcare payment amount plus
-- collected transaction fees.
-- ============================================================

SELECT
    SUM(total_debit_amount) AS total_amount_debited,
    SUM(payment_amount) AS total_healthcare_payments,
    SUM(fee_amount) AS total_fees_collected,
    SUM(payment_amount) + SUM(fee_amount)
        AS reconstructed_total_debit
FROM healthcare_billing.healthcare_transactions
WHERE transaction_status = 'COMPLETED';


-- ============================================================
-- Query 16: ACID verification summary
--
-- Successful transactions:
-- - Create one transaction record.
-- - Debit the payer account.
-- - Credit the receiver account.
-- - Create audit records.
--
-- Failed transactions:
-- - Do not modify account balances.
-- - Are rolled back.
-- - Are recorded separately in failed_transactions.
-- ============================================================

SELECT
    'COMPLETED TRANSACTIONS' AS verification_type,
    COUNT(*) AS record_count
FROM healthcare_billing.healthcare_transactions
WHERE transaction_status = 'COMPLETED'

UNION ALL

SELECT
    'FAILED TRANSACTION ATTEMPTS' AS verification_type,
    COUNT(*) AS record_count
FROM healthcare_billing.failed_transactions

UNION ALL

SELECT
    'BALANCE AUDIT EVENTS' AS verification_type,
    COUNT(*) AS record_count
FROM healthcare_billing.account_balance_audit;
