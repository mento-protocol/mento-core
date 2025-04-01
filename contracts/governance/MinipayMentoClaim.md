The MiniPayMentoClaim would be an ERC1155 token, this standard allows us to define what you can think of as “namespaces” or “sub-tokens” inside of a single token. This would allow us to distribute tokens to Opera for each campaign outlined in the table above. Something like:
tokenId: `march/2025:cashback-promotions` amount: 600k
tokenId: `march/2025:mp-boost` amount: 900k

Opera would need to make a single change to their current distribution mechanism. Instead of calling `cUSD.transfer(user, totalRewardsEarned)` they would need to use a different token standard and specify a list of ids and tokens amount corresponding to amounts earned from each campaign. Using ERC1155’s safeBatchTransferFrom. Something like this:

```
MiniPayMentoClaim.safeBatchTransferFrom(
  operaWallet,
  user,
  [ keccak(“march/2025:cashback-promotions”), keccak(“march/2025:mp-boost”) ],
  [ cashbackPromoAmount, mpBoostAmount ],
  0x0
);
```

MiniPayMentoClaim following ERC1155 standard also gives us an easy way to publish and specify metadata for each campaign, this will then be integrated into the MiniPay Mento dApp to show users how much they have earned in each campaign, and if 0, can be used to show CTAs. The content for this will be stored in the token metadata offchain, with a link on-chain.


