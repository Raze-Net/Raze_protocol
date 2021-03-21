# Raze Protocol
> <img alt="" padding="10 0" src="https://github.com/Raze-Net/Raze_website/blob/main/favicon.png" height="20"> Raze Network
> [raze.network](https://www.raze.network/)

## Project Overview
Raze protects payment anonymity and confidentiality on blockchains. It will consist of frontend clients and backend Smart contracts algorithms, which serve as an agency with proven security and privacy by making use of well-established cryptographic protocols.

Raze Network will apply the [Zether framework](https://eprint.iacr.org/2019/191) to build the second-layer decentralized anonymous payment module. It will be then imported as substrate-based smart contracts. Similar to the Zether framework, it will have three technical modules: mint, transfer and redeem. The mint module will convert a base token into its anonymized version, while the redeem module will convert the anonymized token back to its native form. The transfer module is the one that enables the anonymous transfer of the anonymized token. This process will conceal the transaction amount and guarantee the anonymity for both the sender and receiver.
<p align="center">
  <img src="https://github.com/razenetwork/Raze_Network/blob/main/image/image5.png" alt="" width="70%"/>
</p>

## Project Architecture
The mint module will create a Raze account by running a mint contract and deposit the anonymized token to the Raze account. Each Raze account is identified by a public key `pk` and the mint module will generate a ciphertext under the account public key which encrypts the amount of minted token. If the account has already existed before the mint operation, the generated ciphertext will be homomorphically added to the existing ciphertext to increase the encrypted amount.

Since the balance and transaction amount of each Raze account is encrypted and therefore hidden, the remaining question for the transfer module is how to hide the identities of the involved parties. Similar to the anonymous transfer module of the Zether scheme, we hide the identities of the involved parties through the "one-out-of-many" proof. The "one-out-of-many" proof is conceptually close to ring signature, which proves that a transaction is launched by one of the many parties in the anonymity set (or the ring) while not revealing exactly whom among them is the sender or receiver of the transaction, and thus hide their identities. The transfer module's zkp will also prove the payment consistency and provide a range proof demonstrating there is no negative amount involved in the transaction, which could potentially allow the adversary to create money out of thin air.

The redeem module converts the anonymized token back to its original form. The redeem module also needs to invoke a zero-knowledge proof functionality to prove that the user initiating the redeem module knows the secret key of the corresponding Raze account and the redeemed amount is smaller than the Raze account balance.

To sum up, Raze uses public-key homomorphic encryption to ensure transaction details  remain confidential and uses the "one-out-of-many" proof to hide the sender and receiver identities, and some other zero-knowledge proof schemes are also used to guarantee the payment consistency. Whenever a user deposits a certain amount of token through invoking the mint module, the token is no longer traceable.
