use starknet::ContractAddress;

#[starknet::interface]
trait IBridge<TContractState> {
    fn get_governor(self: @TContractState) -> ContractAddress;
    fn get_l1_bridge(self: @TContractState) -> felt252;
    fn get_l2_token(self: @TContractState) -> ContractAddress;
    fn get_version(self: @TContractState) -> felt252;
    fn get_identity(self: @TContractState) -> felt252;
    fn set_l1_bridge(ref self: TContractState,l1_bridge_address: felt252);
    fn set_l2_token(ref self: TContractState,l2_token_address: ContractAddress);
    fn initiate_withdraw(ref self: TContractState,l1_recipient: felt252, amount: u256);
    //fn handle_deposit(ref self: TContractState,from_address: felt252, account: ContractAddress, amount_low: felt252, amount_high: felt252);
}

#[starknet::contract]
mod Bridge {

    use zeroable::Zeroable;
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::get_caller_address;
    use starknet::send_message_to_l1_syscall;
    use traits::TryInto;
    use traits::Into;
    use option::OptionTrait;
    use integer::BoundedInt;
    use array::ArrayTrait;
    use array::SpanTrait;
    use starknet::EthAddress;
    use starknet::eth_address::Felt252TryIntoEthAddress;
    use satt::SaTT::IERC20DispatcherTrait;
    use satt::SaTT::IERC20Dispatcher;
    use satt::SaTT::IMintableDispatcherTrait;
    use satt::SaTT::IMintableDispatcher;
 
    

    

     #[storage]
    struct Storage {
        _governor: ContractAddress,
        _l1_bridge: felt252,
        _l2_token: ContractAddress,
    }

    const WITHDRAW_MESSAGE: felt252 = 0;
    const CONTRACT_IDENTITY: felt252 = 'STARKGATE';
    const CONTRACT_VERSION: felt252 = 1;


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        L1_Bridge_Set : L1_Bridge_Set,
        L2_Token_Set : L2_Token_Set,
        Withdraw_Initiated:Withdraw_Initiated,
        Deposit_Handled:Deposit_Handled
    }

    #[derive(Drop, starknet::Event)]
    struct L1_Bridge_Set {
        #[key]
        l1_bridge_address: felt252
    }

     #[derive(Drop, starknet::Event)]
    struct L2_Token_Set {
        #[key]
        l2_token_address: ContractAddress
    }

     #[derive(Drop, starknet::Event)]
    struct Withdraw_Initiated {
        #[key]
        l1_recipient: felt252,
        amount:u256,
        caller_address: ContractAddress
    }

     #[derive(Drop, starknet::Event)]
    struct Deposit_Handled {
        #[key]
        account: ContractAddress,
        amount: u256
    }

    #[external(v0)]
    impl Bridge of super::IBridge<ContractState> {

        fn get_governor(self: @ContractState) -> ContractAddress {
            self._governor.read()
        }
        fn get_l1_bridge(self: @ContractState) -> felt252 {
            self._l1_bridge.read()
        }
        fn get_l2_token(self: @ContractState) -> ContractAddress {
            self._l2_token.read()
        }
        fn get_version(self: @ContractState) -> felt252 {
            CONTRACT_VERSION
        }
        fn get_identity(self: @ContractState) -> felt252 {
            CONTRACT_IDENTITY
        }

        fn set_l1_bridge(ref self: ContractState,l1_bridge_address: felt252) {
            InternalFunctions::only_governor(@self);
            let l1_bridge = Bridge::get_l1_bridge(@self);
            assert(l1_bridge.is_zero(), 'l1_bridge is already set');
            let eth: EthAddress = l1_bridge_address.try_into().unwrap();
            self._l1_bridge.write(l1_bridge_address);
            self.emit(Event::L1_Bridge_Set(L1_Bridge_Set{l1_bridge_address:l1_bridge_address}));

        }

        fn set_l2_token(ref self: ContractState,l2_token_address: ContractAddress) {
            InternalFunctions::only_governor(@self);
            let l2_token = Bridge::get_l2_token(@self);
            assert(l2_token.is_zero(), 'l2_token is already set');
            assert(l2_token_address.is_non_zero(), 'l2_token_address is set to 0');
            self._l2_token.write(l2_token_address);
            self.emit(Event::L2_Token_Set(L2_Token_Set{l2_token_address:l2_token_address}));

        }

        fn initiate_withdraw(ref self: ContractState,l1_recipient: felt252, amount: u256) {
            let l1_bridge = Bridge::get_l1_bridge(@self);
            let l2_token = Bridge::get_l2_token(@self);
            assert(l2_token.is_non_zero(), 'l2_token is not set');
            assert(l1_bridge.is_non_zero(), 'l1_bridge is not set');
            let eth: EthAddress = l1_recipient.try_into().unwrap();
            assert(amount != BoundedInt::min(), 'amount is 0');

            let caller = get_caller_address();
            let bal_before = IERC20Dispatcher { contract_address: l2_token }.balance_of(caller);
            assert(amount <= bal_before, 'not enough balance');

            let burn_res = IMintableDispatcher {
                contract_address: l2_token
            }.permissionedBurn(caller, amount);

            let bal_after = IERC20Dispatcher { contract_address: l2_token }.balance_of(caller);

            assert(bal_after + amount == bal_before, 'balances not valid');

            let mut payload = ArrayTrait::new();
            payload.append(WITHDRAW_MESSAGE);
            payload.append(l1_recipient);
            payload.append(amount.low.into());
            payload.append(amount.high.into());
            send_message_to_l1_syscall(l1_bridge, payload.span()).unwrap_syscall();

            self.emit(Event::Withdraw_Initiated(Withdraw_Initiated{l1_recipient:l1_recipient,amount:amount,caller_address:caller }));

            
        }

        

    }


   #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
         #[inline(always)]
         fn only_governor(self: @ContractState) {
            let caller = get_caller_address();
            let governor = Bridge::get_governor(self);
            assert(governor.is_non_zero(), 'governor is set to 0');
            assert(caller == governor, 'GOVERNOR_ONLY');
         }
    }

   

    #[constructor]
    fn constructor(ref self: ContractState,governor: ContractAddress) {
        assert(governor.is_non_zero(), 'governor is set to 0');
        self._governor.write(governor);
    }

     #[l1_handler]
        fn handle_deposit(ref self: ContractState,from_address: felt252, account: ContractAddress, amount_low: felt252, amount_high: felt252) {
            assert(account.is_non_zero(), 'account is 0');
            let l1_bridge = Bridge::get_l1_bridge(@self);
            let l2_token = Bridge::get_l2_token(@self);
            assert(l2_token.is_non_zero(), 'l2_token is not set');
            assert(l1_bridge.is_non_zero(), 'l1_bridge is not set');
            assert(from_address == l1_bridge, 'BRIDGE_ONLY');
            let amount = u256 {
                low: amount_low.try_into().unwrap(), high: amount_high.try_into().unwrap()
            };
            let bal_before = IERC20Dispatcher { contract_address: l2_token }.balance_of(account);
            let expected_balance_after = bal_before + amount;
            let mint_res = IMintableDispatcher {
                contract_address: l2_token
            }.permissionedMint(account, amount);
            let bal_after = IERC20Dispatcher { contract_address: l2_token }.balance_of(account);
            assert(bal_after == expected_balance_after, 'expected not valid');
            self.emit(Event::Deposit_Handled(Deposit_Handled{account:account,amount:amount }));

        }

}

//account 0x05732a399b4933b07384a0b7208f31aa67b3d4cbd7d67e5676e40fd4276e35b1

//classs bridge l2  0x01520820f146bb323db3e7a4fc2aa78936bdeb6b5a517c7667dea5db5781d30e
//ctr bridge  2 0x056eb18fab0f313b4e01566b961ec49954ceaa0859d69b33f1c497028c2e1898

//class erc20 0x0505b527b78824b3c3e2e00e28794d97790b96114355eb5591388c095a84e39d
// ctr erc20 0x00f72a46c598d8448896cb4a1075f9069d0202c1e918e65ac2039b76673616fa

//l1 bridge 0x2E595570CD04389bFADa2f8a8FDC7Df0815cade0
//l1 erc20

//satt campaign class 0x000c7a332e738b7c492f625d266c57f24d5f53d7bc7879959b3595cb4e0a339b

//satt factory class 0x05c6ce2b951ce0cf0c41a6d709aee9d53ef1d9aa12bf3dff3eb34cdeb9ddbc4d
// satt factory contract 0x046fe16ca86e25ce7238e7f30b814cbc8b65ff76355e587c21b3610902b24dab