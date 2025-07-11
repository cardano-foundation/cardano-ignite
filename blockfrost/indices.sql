-- https://github.com/blockfrost/blockfrost-backend-ryo#indices
CREATE INDEX IF NOT EXISTS bf_idx_block_hash_encoded ON block USING HASH (encode(hash, 'hex'));
CREATE INDEX IF NOT EXISTS bf_idx_datum_hash ON datum USING HASH (encode(hash, 'hex'));
CREATE INDEX IF NOT EXISTS bf_idx_multi_asset_policy ON multi_asset USING HASH (encode(policy, 'hex'));
CREATE INDEX IF NOT EXISTS bf_idx_multi_asset_policy_name ON multi_asset USING HASH ((encode(policy, 'hex') || encode(name, 'hex')));
CREATE INDEX IF NOT EXISTS bf_idx_pool_hash_view ON pool_hash USING HASH (view);
CREATE INDEX IF NOT EXISTS bf_idx_redeemer_data_hash ON redeemer_data USING HASH (encode(hash, 'hex'));
CREATE INDEX IF NOT EXISTS bf_idx_scripts_hash ON script USING HASH (encode(hash, 'hex'));
CREATE INDEX IF NOT EXISTS bf_idx_tx_hash ON tx USING HASH (encode(hash, 'hex'));
CREATE UNIQUE INDEX IF NOT EXISTS bf_u_idx_epoch_stake_epoch_and_id ON epoch_stake (epoch_no, id);
CREATE INDEX IF NOT EXISTS bf_idx_reference_tx_in_tx_in_id ON reference_tx_in (tx_in_id);
CREATE INDEX IF NOT EXISTS bf_idx_collateral_tx_in_tx_in_id ON collateral_tx_in (tx_in_id);
CREATE INDEX IF NOT EXISTS bf_idx_redeemer_script_hash ON redeemer USING HASH (encode(script_hash, 'hex'));
CREATE INDEX IF NOT EXISTS bf_idx_redeemer_tx_id ON redeemer USING btree (tx_id);
CREATE INDEX IF NOT EXISTS bf_idx_col_tx_out ON collateral_tx_out USING btree (tx_id);
CREATE INDEX IF NOT EXISTS bf_idx_ma_tx_mint_ident ON ma_tx_mint USING btree (ident);
CREATE INDEX IF NOT EXISTS bf_idx_ma_tx_out_ident ON ma_tx_out USING btree (ident);
CREATE INDEX IF NOT EXISTS bf_idx_reward_rest_addr_id ON reward_rest USING btree (addr_id);
CREATE INDEX IF NOT EXISTS bf_idx_reward_rest_spendable_epoch ON reward_rest USING btree (spendable_epoch);
CREATE INDEX IF NOT EXISTS bf_idx_drep_hash_raw ON drep_hash USING hash (raw);
CREATE INDEX IF NOT EXISTS bf_idx_drep_hash_view ON drep_hash USING hash (view);
CREATE INDEX IF NOT EXISTS bf_idx_drep_hash_has_script ON drep_hash USING hash (has_script);
CREATE INDEX IF NOT EXISTS bf_idx_delegation_vote_addr_id ON delegation_vote USING hash (addr_id);

-- https://github.com/IntersectMBO/cardano-db-sync/issues/1349#issuecomment-1416017488
CREATE UNIQUE INDEX IF NOT EXISTS unique_ada_pots ON ada_pots USING btree (block_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_col_txin ON collateral_tx_in USING btree (tx_in_id, tx_out_id, tx_out_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_col_txout ON collateral_tx_out USING btree (tx_id, index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_delegation ON delegation USING btree (tx_id, cert_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_epoch_param ON epoch_param USING btree (epoch_no, block_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_ma_tx_mint ON ma_tx_mint USING btree (ident, tx_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_ma_tx_out ON ma_tx_out USING btree (ident, tx_out_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_param_proposal ON param_proposal USING btree (key, registered_tx_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_pool_owner ON pool_owner USING btree (addr_id, pool_update_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_pool_relay ON pool_relay USING btree (update_id, ipv4, ipv6, dns_name);
CREATE UNIQUE INDEX IF NOT EXISTS unique_pool_retiring ON pool_retire USING btree (announced_tx_id, cert_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_pool_update ON pool_update USING btree (registered_tx_id, cert_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_pot_transfer ON pot_transfer USING btree (tx_id, cert_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_redeemer ON redeemer USING btree (tx_id, purpose, index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_ref_tx_in ON reference_tx_in USING btree (tx_in_id, tx_out_id, tx_out_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_reserves ON reserve USING btree (addr_id, tx_id, cert_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_stake_deregistration ON stake_deregistration USING btree (tx_id, cert_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_stake_registration ON stake_registration USING btree (tx_id, cert_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_treasury ON treasury USING btree (addr_id, tx_id, cert_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_tx_metadata ON tx_metadata USING btree (key, tx_id);
CREATE UNIQUE INDEX IF NOT EXISTS unique_txin ON tx_in USING btree (tx_out_id, tx_out_index);
CREATE UNIQUE INDEX IF NOT EXISTS unique_withdrawal ON withdrawal USING btree (addr_id, tx_id);
