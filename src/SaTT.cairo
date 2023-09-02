use starknet::ContractAddress;

#[starknet::interface]
trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
trait IMintable<TContractState> {
    fn permittedMinter(self: @TContractState) -> ContractAddress;
    fn permissionedMint(ref self: TContractState,account: ContractAddress, amount: u256) -> bool;
    fn permissionedBurn(ref self: TContractState,account: ContractAddress, amount: u256) -> bool;
    fn owner(self: @TContractState) -> ContractAddress;
    fn transferOwnership(ref self: TContractState,new_owner: ContractAddress);
    fn renounceOwnership(ref self: TContractState);
     fn setMinter(ref self: TContractState,new_minter: ContractAddress);
}

#[starknet::contract]
mod SaTT {
    use super::IERC20;
    use super::IMintable;
    use integer::BoundedInt;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use zeroable::Zeroable;

     #[storage]
    struct Storage {
        _name: felt252,
        _symbol: felt252,
        _total_supply: u256,
        _balances: LegacyMap<ContractAddress, u256>,
        _allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
        _owner: ContractAddress,
        _permitted_minter: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        OwnershipTransferred:OwnershipTransferred
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        previous_owner: ContractAddress,
        new_owner: ContractAddress,
    }


     #[external(v0)]
    impl ERC20Impl of IERC20<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self._name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
             self._symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            18_u8
        }

        fn total_supply(self: @ContractState) -> u256 {
             self._total_supply.read()
        }

        fn balance_of(self: @ContractState,account: ContractAddress) -> u256 {
             self._balances.read(account)
        }

        fn allowance(self: @ContractState,owner: ContractAddress, spender: ContractAddress) -> u256 {
             self._allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState,recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            InternalImpl::_transfer(ref self,sender, recipient, amount);
            true
        }

        fn transfer_from(ref self: ContractState,sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            InternalImpl::_spend_allowance(ref self,sender, caller, amount);
            InternalImpl::_transfer(ref self,sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState,spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            InternalImpl::_approve(ref self,caller, spender, amount);
            true
        }
    }

    #[external(v0)]
    impl Mintable of IMintable<ContractState> {
        fn permittedMinter(self: @ContractState) -> ContractAddress {
            self._permitted_minter.read()
        }

        fn permissionedMint(ref self: ContractState,account: ContractAddress, amount: u256) -> bool {
            InternalImpl::permitted_minter_only(@self);
            InternalImpl::_mint(ref self,account, amount);
            true
        }

        fn permissionedBurn(ref self: ContractState,account: ContractAddress, amount: u256) -> bool {
            InternalImpl::permitted_minter_only(@self);
            InternalImpl::_burn(ref self,account, amount);
            true
        }

       
        fn owner(self: @ContractState) -> ContractAddress {
            self._owner.read()
        }

        
        fn transferOwnership(ref self: ContractState,new_owner: ContractAddress) {
            assert(!new_owner.is_zero(), 'New owner is the zero address');
            InternalImpl::assert_only_owner(@self);
            InternalImpl::_transfer_ownership(ref self,new_owner);
        }

       
        fn renounceOwnership(ref self: ContractState) {
            InternalImpl::assert_only_owner(@self);
            InternalImpl::_transfer_ownership(ref self,Zeroable::zero());
        }

        

        
        fn setMinter(ref self: ContractState,new_minter: ContractAddress) {
            assert(!new_minter.is_zero(), 'New minter is the zero address');
            InternalImpl::assert_only_owner(@self);
            self._permitted_minter.write(new_minter);
            
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        recipient: ContractAddress,
        minter: ContractAddress
    ) {
        InternalImpl::initializer(ref self,name, symbol);
        InternalImpl::_transfer_ownership(ref self,recipient);
        InternalImpl::permitted_initializer(ref self,minter);
        InternalImpl::_mint(ref self,recipient, initial_supply);
    }



     #[generate_trait]
    impl InternalImpl of InternalTrait {

   
        fn initializer(ref self: ContractState,name_: felt252, symbol_: felt252) {
            self._name.write(name_);
            self._symbol.write(symbol_);
        }

    
        fn permitted_initializer(ref self: ContractState,permitted: ContractAddress) {
            self._permitted_minter.write(permitted);
        }

        
        fn _increase_allowance(ref self: ContractState,spender: ContractAddress, added_value: u256) -> bool {
            let caller = get_caller_address();
            InternalImpl::_approve(ref self,caller, spender, self._allowances.read((caller, spender)) + added_value);
            true
        }

        
        fn _decrease_allowance(ref self: ContractState,spender: ContractAddress, subtracted_value: u256) -> bool {
            let caller = get_caller_address();
            InternalImpl::_approve(ref self,caller, spender, self._allowances.read((caller, spender)) - subtracted_value);
            true
        }

    
        fn _mint(ref self: ContractState,recipient: ContractAddress, amount: u256) {
            assert(!recipient.is_zero(), 'ERC20: mint to 0');
            self._total_supply.write(self._total_supply.read() + amount);
            self._balances.write(recipient, self._balances.read(recipient) + amount);
            self.emit(Transfer{from:Zeroable::zero(),to:recipient,value:amount});
        }

    
        fn _burn(ref self: ContractState,account: ContractAddress, amount: u256) {
            assert(!account.is_zero(), 'ERC20: burn from 0');
            self._total_supply.write(self._total_supply.read() - amount);
            self._balances.write(account, self._balances.read(account) - amount);
            self.emit(Transfer{from:account,to:Zeroable::zero(),value:amount});
            
        }

        
        fn _approve(ref self: ContractState,owner: ContractAddress, spender: ContractAddress, amount: u256) {
            assert(!owner.is_zero(), 'ERC20: approve from 0');
            assert(!spender.is_zero(), 'ERC20: approve to 0');
            self._allowances.write((owner, spender), amount);
            self.emit(Approval{owner, spender, value:amount});
        }

    
        fn _transfer(ref self: ContractState,sender: ContractAddress, recipient: ContractAddress, amount: u256) {
            assert(!sender.is_zero(), 'ERC20: transfer from 0');
            assert(!recipient.is_zero(), 'ERC20: transfer to 0');
            self._balances.write(sender, self._balances.read(sender) - amount);
            self._balances.write(recipient, self._balances.read(recipient) + amount);
             self.emit(Transfer{from:sender,to:recipient,value:amount});
          
        }

    
        fn _spend_allowance(ref self: ContractState,owner: ContractAddress, spender: ContractAddress, amount: u256) {
            let current_allowance = self._allowances.read((owner, spender));
            if current_allowance != BoundedInt::max() {
                InternalImpl::_approve(ref self,owner, spender, current_allowance - amount);
            }
        }

    
        fn permitted_minter_only(self: @ContractState) {
            let caller = get_caller_address();
            let minter = Mintable::permittedMinter(self);
            assert(!minter.is_zero(), 'minter is set to 0');
            assert(caller == minter, 'unauthorized mint or burn');
        }

        
        fn _transfer_ownership(ref self: ContractState,new_owner: ContractAddress) {
            let previous_owner: ContractAddress = self._owner.read();
            self._owner.write(new_owner);
            self.emit(OwnershipTransferred{previous_owner, new_owner});
        }

        
        fn assert_only_owner(self: @ContractState) {
            let owner: ContractAddress = self._owner.read();
            let caller: ContractAddress = get_caller_address();
            assert(!caller.is_zero(), 'Caller is the zero address');
            assert(caller == owner, 'Caller is not the owner');
        }
    }


    
}
