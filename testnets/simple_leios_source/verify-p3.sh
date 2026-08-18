echo "Stake:"
docker logs p3 2>&1 | grep 'resolved stake distribution'   # our_stake must be NON-ZERO
echo "Produced block:"
docker logs p3 2>&1 | grep 'produced block'                # block_no ~ network_tip+1
# adoption by the real Haskell nodes:
echo "Haskell adoption:"
docker logs p2 2>&1 | grep  'AddedToCurrentChain' | tail -n 10       # then filter by issuerHash below
