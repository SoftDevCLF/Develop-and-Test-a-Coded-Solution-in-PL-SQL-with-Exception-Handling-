--WKIS Company program for accounting system
-- •	This is a double-entry accounting system that uses the accounting rules presented in the Accounting Notes document in Brightspace.
-- •	Take transactions from a holding table named NEW_TRANSACTIONS and insert them into the TRANSACTION_DETAIL and TRANSACTION_HISTORY tables.
-- •	At the same time, update the appropriate account balance in the ACCOUNT table. 
-- •	You need to determine the default transaction type of an account (debit (D) or credit (C)) to decide whether to add or subtract when updating the account balance. 
-- •	Once a transaction is successfully processed, it should be removed from the holding table.


DECLARE
  --Outer cursor to fetch records from new_transactions
  CURSOR c_transaction IS
    SELECT DISTINCT transaction_no, transaction_date, description
    FROM new_transactions
    ORDER BY transaction_no;

  --Inner cursor for all rows belonging to one transaction
  CURSOR c_transaction_details(p_no NUMBER) IS
    SELECT nt.account_no,
           nt.transaction_type,
           nt.transaction_amount,
           at.default_trans_type
    FROM new_transactions nt
    JOIN account a ON nt.account_no = a.account_no
    JOIN account_type at ON a.account_type_code = at.account_type_code
    WHERE nt.transaction_no = p_no;

  --Variables
  total_debits NUMBER;
  total_credits NUMBER;
  error_found BOOLEAN;

BEGIN
  --Outer Loop through each distinct transaction in new_transactions
  FOR r_transaction IN c_transaction LOOP
    total_debits := 0;
    total_credits := 0;
    error_found := FALSE;

    --Missing (Null) Transactions
    IF r_transaction.transaction_no IS NULL THEN
      INSERT INTO wkis_error_log(transaction_no, transaction_date, description, error_msg)
      VALUES(NULL, r_transaction.transaction_date, r_transaction.description, 
             'Missing transaction number. Cannot process transaction.');
      error_found := TRUE;
    END IF;

    --If error occurs skip entire transaction
    IF error_found THEN
      NULL; -- skip to next transaction
    ELSE

      --Sum of debits and credits
      FOR r_detail IN c_transaction_details(r_transaction.transaction_no) LOOP
        IF r_detail.transaction_type = 'D' THEN
          total_debits := total_debits + r_detail.transaction_amount;
        ELSIF r_detail.transaction_type = 'C' THEN
          total_credits := total_credits + r_detail.transaction_amount;
        END IF;
      END LOOP;

      --Check debits ≠ credits
      IF total_debits != total_credits THEN
        INSERT INTO wkis_error_log(transaction_no, transaction_date, description, error_msg)
        VALUES(r_transaction.transaction_no, r_transaction.transaction_date, r_transaction.description,
        'The debits and credits are not equal in this transaction.');
        error_found := TRUE;
      END IF;

      --If still no error, insert history then detail rows 
      IF NOT error_found THEN

        --Insert transaction history
        INSERT INTO transaction_history(transaction_no, transaction_date, description)
        VALUES(r_transaction.transaction_no, r_transaction.transaction_date, r_transaction.description);

        --Now insert detail rows and update accounts
        FOR r_detail IN c_transaction_details(r_transaction.transaction_no) LOOP

          --Insert into transaction_detail
          INSERT INTO transaction_detail(account_no, transaction_no, transaction_type, transaction_amount)
          VALUES (r_detail.account_no, r_transaction.transaction_no, r_detail.transaction_type, r_detail.transaction_amount);

          --Update account balance based on transaction type
          IF r_detail.transaction_type = r_detail.default_trans_type THEN
            UPDATE account
            SET account_balance = account_balance + r_detail.transaction_amount
            WHERE account_no = r_detail.account_no;
          ELSE
            UPDATE account
            SET account_balance = account_balance - r_detail.transaction_amount
            WHERE account_no = r_detail.account_no;
          END IF;

        END LOOP;

        --Remove processed rows from holding table
        DELETE FROM new_transactions
        WHERE transaction_no = r_transaction.transaction_no;

      END IF;
    END IF;
  END LOOP;


  --Commit the Changes
  COMMIT;
END;
/

