use starknet::ContractAddress;
use starknet::ClassHash;

#[starknet::interface]
trait IFactory<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn campaign_hash(self: @TContractState) -> ClassHash;
    fn oracle(self: @TContractState) -> ContractAddress;
    fn set_campaign_hash(ref self:TContractState ,cmp:ClassHash);
    fn set_owner(ref self:TContractState ,new:ContractAddress);
    fn set_oracle(ref self:TContractState ,new:ContractAddress);
    fn createCampaign(ref self:TContractState ,url_first:felt252,url_last:felt252, startDate:u64,endDate:u64,amount:u256,token:ContractAddress,idSn:u8,viewRatio:u64,likeRatio:u64,shareRatio:u64);
    fn ask(ref self:TContractState ,id:felt252);
    fn answer(ref self:TContractState ,id:felt252,campaign:ContractAddress,views:u64,likes:u64,shares:u64);
}


#[starknet::contract]
mod Factory {

    use core::traits::Into;
    use zeroable::Zeroable;
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::ClassHash;
    use starknet::class_hash::ClassHashZeroable; 
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::deploy_syscall;
    use starknet::get_tx_info;
    use starknet::get_block_info;
    use starknet::info::ExecutionInfo;
    use starknet::info::BlockInfo;
    use starknet::info::TxInfo;
    use array::ArrayTrait;
    use array::SpanTrait;
    use satt::Campaign::ICampaignDispatcherTrait;
    use satt::Campaign::ICampaignDispatcher;
    

     #[storage]
    struct Storage {
        _campaign_hash: ClassHash,
        _campaigns : LegacyMap<ContractAddress,bool>,
        _oracle : ContractAddress,
        _owner:ContractAddress
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CampaignCreated: CampaignCreated,
        Request: Request,
    }

    #[derive(Drop, starknet::Event)]
    struct CampaignCreated {
        id:ContractAddress,
        url_first:felt252,
        url_last:felt252,
        advertiser:ContractAddress,
        startDate:u64,
        endDate:u64,
        idSn:u8,
        viewRatio:u64,
        likeRatio:u64,
        shareRatio:u64
    }

   #[derive(Drop, starknet::Event)]
   struct Request {
        campaign:ContractAddress,
        id:felt252,
        idSn:u8,
        idUser:felt252,
        idPost:felt252
   }
    

   #[external(v0)]
    impl Factory of super::IFactory<ContractState> {

       
        fn owner(self: @ContractState) -> ContractAddress {
            self._owner.read()
        }

       
        fn campaign_hash(self: @ContractState) -> ClassHash {
            self._campaign_hash.read()
        }

       
        fn oracle(self: @ContractState) -> ContractAddress {
            self._oracle.read()
        }

        fn set_campaign_hash(ref self: ContractState,cmp:ClassHash) {
        assert(cmp.is_non_zero(), 'owner is set to 0');
         InternalImpl::only_owner(@self);
        self._campaign_hash.write(cmp);
        }

      
        fn set_owner(ref self: ContractState,new:ContractAddress) {
            assert(new.is_non_zero(), 'owner is set to 0');
            InternalImpl::only_owner(@self);
            self._owner.write(new);
        }

       
        fn set_oracle(ref self: ContractState,new:ContractAddress) {
            assert(new.is_non_zero(), 'oracle is set to 0');
            InternalImpl::only_owner(@self);
            self._oracle.write(new);
        }

       
        fn createCampaign(ref self: ContractState,url_first:felt252,url_last:felt252, startDate:u64,endDate:u64,amount:u256,token:ContractAddress,idSn:u8,viewRatio:u64,likeRatio:u64,shareRatio:u64) {
            let hash = self._campaign_hash.read();
            let mut calldata = ArrayTrait::new();
            calldata.append(url_first);
            calldata.append(url_last);
            calldata.append(startDate.into());
            calldata.append(endDate.into());
            calldata.append(amount.low.into());
            calldata.append(amount.high.into());
            calldata.append(token.into());
            calldata.append(idSn.into());
            calldata.append(viewRatio.into());
            calldata.append(likeRatio.into());
            calldata.append(shareRatio.into());
            let (addr,ret) = deploy_syscall(hash,0,calldata.span(),false).unwrap_syscall();
            self._campaigns.write(addr,true);
            let caller = get_caller_address();
            self.emit(CampaignCreated {id:addr,url_first,url_last,advertiser:caller,startDate,endDate,idSn,viewRatio,likeRatio,shareRatio});
            
        }
        

       
        fn ask(ref self: ContractState,id:felt252) {
            let caller = get_caller_address();
            InternalImpl::only_campaign(@self);
            let (idSn,idUser,idPost) = ICampaignDispatcher { contract_address: caller }.prom(id);
            self.emit(Request{campaign:caller,id, idSn,idUser,idPost});
           

        }

       
        fn answer(ref self: ContractState,id:felt252,campaign:ContractAddress,views:u64,likes:u64,shares:u64) {
            InternalImpl::only_oracle(@self);
            assert(self._campaigns.read(campaign), 'CAMPAIGN_ONLY');
            let res = ICampaignDispatcher { contract_address: campaign }.update(id,views,likes,shares);
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState,owner:ContractAddress) {
         assert(owner.is_non_zero(), 'owner is set to 0');
        self._owner.write(owner);
    }
    
    #[generate_trait]
    impl InternalImpl of InternalTrait {

    
        fn only_owner(self: @ContractState) {
            let caller = get_caller_address();
            let owner = self._owner.read();
            assert(caller == owner, 'OWNER_ONLY');
        }

        
        fn only_oracle(self: @ContractState) {
            let caller = get_caller_address();
            let oracle = self._oracle.read();
            assert(caller == oracle, 'OWNER_ONLY');
        }

        
        fn only_campaign(self: @ContractState) {
            let caller = get_caller_address();
            assert(self._campaigns.read(caller), 'CAMPAIGN_ONLY');
        }
    }


    

    
}