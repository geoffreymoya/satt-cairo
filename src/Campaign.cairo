use starknet::ContractAddress;

#[starknet::interface]
trait ICampaign<TContractState> {
    fn factory(self: @TContractState) -> ContractAddress;
    fn prom(self: @TContractState,id:felt252) -> (u8,felt252,felt252);
    fn url(self: @TContractState) -> (felt252,felt252);
    fn advertiser(self: @TContractState) -> ContractAddress;
    fn dates(self: @TContractState) -> (u64,u64);
    fn funds(self: @TContractState) -> (ContractAddress,u256);
    fn sn(self: @TContractState) -> u8;
    fn ratios(self: @TContractState) -> (u64,u64,u64);

    fn apply(ref self : TContractState,idUser:felt252,idPost:felt252);
    fn validate(ref self : TContractState,id:felt252);
    fn reject(ref self : TContractState,id:felt252,reason:felt252);
    fn fund(ref self : TContractState,amount:u256);
    fn ask(ref self : TContractState,id:felt252);
    fn update(ref self : TContractState,id:felt252,views:u64,likes:u64,shares:u64);
    fn pay(ref self : TContractState,id:felt252);
    fn withdraw(ref self : TContractState);
}

#[starknet::contract]
mod Campaign {

    use traits::TryInto;
    use traits::Into;
    use option::OptionTrait;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::get_tx_info;
    use starknet::get_block_info;
    use starknet::info::ExecutionInfo;
    use starknet::info::BlockInfo;
    use starknet::info::TxInfo;
    use satt::SaTT::IERC20DispatcherTrait;
    use satt::SaTT::IERC20Dispatcher;
    use satt::Factory::IFactoryDispatcherTrait;
    use satt::Factory::IFactoryDispatcher;
    use box::BoxTrait;

    const STATUS_NEW: felt252 = 0;
    const STATUS_VALID: felt252 = 1;
    const STATUS_REJECT: felt252 = 2;

    #[storage]
    struct Storage {
        _factory:ContractAddress,
        _token : ContractAddress,
        _advertiser:ContractAddress,
        _url_first:felt252,
        _url_last:felt252,
        _idSn:u8,
        _viewRatio:u64,
        _likeRatio:u64,
        _shareRatio:u64,
        _startDate:u64,
        _endDate:u64,
        _funds:u256,

        _influencer :LegacyMap<felt252,ContractAddress>,
        _status: LegacyMap<felt252,felt252>,
        _amount:LegacyMap<felt252,u256>,
        _pendingAmount:LegacyMap<felt252,u256>,
        _idUser:LegacyMap<felt252,felt252>,
        _idPost:LegacyMap<felt252,felt252>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Applied: Applied,
        Accepted: Accepted,
        Rejected:Rejected,
        Funded:Funded,
        Pay:Pay,
        Result:Result,
        Redeem:Redeem,
        OutOfFunds:OutOfFunds
    }

    #[derive(Drop, starknet::Event)]
    struct Applied {
        prom:felt252,
        influencer:ContractAddress,
        idUser:felt252,
        idPost:felt252
    }

    #[derive(Drop, starknet::Event)]
    struct Accepted {
        prom:felt252
    }

     #[derive(Drop, starknet::Event)]
    struct Rejected {
       prom:felt252,
       reason:felt252
    }

     #[derive(Drop, starknet::Event)]
    struct Funded {
        token:ContractAddress,
        amount:u256
    }

     #[derive(Drop, starknet::Event)]
    struct Pay {
        prom:felt252,
        amount:u256
    }

    #[derive(Drop, starknet::Event)]
    struct Result {
        prom:felt252,
        views:u64,
        likes:u64,
        shares:u64
    }

    #[derive(Drop, starknet::Event)]
    struct Redeem {
        amount:u256
    }

    #[derive(Drop, starknet::Event)]
    struct OutOfFunds {
       
    }
   
    #[external(v0)]
    impl Campaign of super::ICampaign<ContractState> {

        
        fn factory(self: @ContractState) -> ContractAddress {
            self._factory.read()
        }

       
        fn prom(self: @ContractState,id:felt252) -> (u8,felt252,felt252) {
        
            let idUser = self._idUser.read(id);
            let idPost = self._idPost.read(id);
            let idSn = self._idSn.read();
            (idSn,idUser,idPost)
        }

        
        fn url(self: @ContractState) -> (felt252,felt252) {
            let urlFirst = self._url_first.read();
            let urlLast = self._url_last.read();
            (urlFirst,urlLast)
        }

        
        fn dates(self: @ContractState) -> (u64,u64) {
            let start = self._startDate.read();
            let end = self._endDate.read();
            (start,end)
        }

        
        fn advertiser(self: @ContractState) -> ContractAddress {
            let advertiser = self._advertiser.read();
            advertiser
        }


   
        fn funds(self: @ContractState) -> (ContractAddress,u256) {
        
            let token = self._token.read();
            let funds = self._funds.read();   
        (token,funds)
        }



       
        fn sn(self: @ContractState) -> u8 {
            let idSn = self._idSn.read();
            idSn
        }

        
        fn ratios(self: @ContractState) -> (u64,u64,u64) {
        
            
            let view = self._viewRatio.read();
            let like = self._likeRatio.read();
            let share = self._shareRatio.read();
            (view,like,share)
        }

        
        fn apply(ref self : ContractState,idUser:felt252,idPost:felt252) {
            InternalImpl::is_active(@self);
            let block = get_block_info().unbox().block_number;
            let caller = get_caller_address();
            let id = pedersen(pedersen(pedersen(idUser,idPost),block.into()),caller.into());

            self._influencer.write(id,caller);
            self._status.write(id,STATUS_NEW);
            self._amount.write(id,u256 {low:0,high:0});
            self._pendingAmount.write(id,u256 {low:0,high:0});
            self._idUser.write(id,idUser);
            self._idPost.write(id,idPost);

            self.emit(Applied{prom:id,influencer:caller,idUser,idPost});
           
        }

        
        fn validate(ref self : ContractState,id:felt252) {
            InternalImpl::only_advertiser(@self);
            InternalImpl::is_active(@self);
            InternalImpl::is_new(@self,id); 
            self._status.write(id,STATUS_VALID);
            self.emit(Accepted{prom:id});
           
        }

        
        fn reject(ref self : ContractState,id:felt252,reason:felt252) {
            InternalImpl::only_advertiser(@self);
            InternalImpl::is_new(@self,id); 
            self._status.write(id,STATUS_REJECT);
            self.emit(Rejected{prom:id,reason});
            
        }

        
        fn fund(ref self : ContractState,amount:u256) {
            InternalImpl::is_active(@self);
            InternalImpl::fundCampaign(ref self,amount);
        }

        
        fn ask(ref self : ContractState,id:felt252) {
            InternalImpl::is_active(@self);
        
            let factory = self._factory.read();
            let status = self._status.read(id);
            assert(status == STATUS_VALID,'prom not accepted');
            let res = IFactoryDispatcher { contract_address: factory }.ask(id);
        }

       
        fn update(ref self : ContractState,id:felt252,views:u64,likes:u64,shares:u64) {
            InternalImpl::only_factory(@self);
            
            let oldFunds = self._funds.read();
            let viewRatio = self._viewRatio.read();
            let likeRatio = self._likeRatio.read();
            let shareRatio = self._shareRatio.read();
            let oldTotal = self._amount.read(id);
            let oldPending = self._pendingAmount.read(id);
            let rawTotal:felt252 = (views*viewRatio + likes*likeRatio + shares*shareRatio).into();
            let newTotal:u256 = rawTotal.into();
            let mut diff = u256 {low:0,high:0};
            let mut newFunds = u256 {low:0,high:0};

            if (newTotal - oldTotal) >= oldFunds {
                diff = oldFunds;
                self.emit(OutOfFunds{});
            }
            else {
            
                diff = newTotal - oldTotal;
                newFunds = oldFunds - diff;
            }
            
            self._funds.write(newFunds);
            self._amount.write(id,newTotal);
            self._pendingAmount.write(id,oldPending + diff);

            self.emit(Result{prom:id,views,likes,shares});
            
        }


       
        fn pay(ref self : ContractState,id:felt252) {
        
            let token = self._token.read();
            let influencer = self._influencer.read(id);
            let pendingAmount = self._pendingAmount.read(id);
            self._pendingAmount.write(id,u256 {low:0,high:0});
            let res = IERC20Dispatcher { contract_address: token }.transfer(influencer,pendingAmount);

            self.emit(Pay{prom:id,amount:pendingAmount});
           
        }

       
        fn withdraw(ref self : ContractState) {
            InternalImpl::only_advertiser(@self);
            InternalImpl::is_ended(@self);
            let token = self._token.read();
            let advertiser = self._advertiser.read();
            let amount = self._funds.read();
            self._funds.write(u256 {low:0,high:0});
            let res = IERC20Dispatcher { contract_address: token }.transfer(advertiser,amount);
            self.emit(Redeem{amount});
           
        }

    }

   
    

    #[constructor]
    fn constructor(ref self : ContractState,url_first:felt252,url_last:felt252, startDate:u64,endDate:u64,amount:u256,token:ContractAddress,idSn:u8,viewRatio:u64,likeRatio:u64,shareRatio:u64) {
        let block_info = get_block_info().unbox();
        let tx_info = get_tx_info().unbox();
        let caller = get_caller_address();
        assert(block_info.block_timestamp < startDate,'start date too early');
        assert(startDate < endDate,'end date too early');

        self._url_first.write(url_first);
        self._url_last.write(url_last);
        self._advertiser.write(tx_info.account_contract_address);
        self._factory.write(caller);
        self._token.write(token);
        self._startDate.write(startDate);
        self._endDate.write(endDate);
        self._idSn.write(idSn);
        self._viewRatio.write(viewRatio);
        self._likeRatio.write(likeRatio);
        self._shareRatio.write(shareRatio);

        InternalImpl::fundCampaign(ref self,amount);
        

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

         
        fn fundCampaign(ref self: ContractState,amount:u256) {
            let token = self._token.read();
            let from = self._advertiser.read();
            let thisCtr = get_contract_address();
            let res = IERC20Dispatcher { contract_address: token }.transfer_from(from,thisCtr,amount);
            let prev_funds = self._funds.read();
            self._funds.write(amount+prev_funds);

            self.emit(Funded{token,amount});
           
        }
        
        
        fn only_advertiser(self: @ContractState) {
            let caller = get_caller_address();
            let advertiser = self._advertiser.read();
            assert(caller == advertiser, 'ADVERTISER_ONLY');
        }

       
        fn only_factory(self: @ContractState) {
            let caller = get_caller_address();
            let factory = self._factory.read();
            assert(caller == factory, 'FACTORY_ONLY');
        }

       
        fn is_active(self: @ContractState) {
            let block = get_block_info().unbox();
            let endDate = self._endDate.read();
            assert(block.block_timestamp < endDate,'campaign ended');
        }

        
        fn is_ended(self: @ContractState) {
            let block = get_block_info().unbox();
            let endDate = self._endDate.read();
            assert(block.block_timestamp > endDate,'campaign not ended');
        }

        
        fn is_new(self: @ContractState,id:felt252) {
            let status = self._status.read(id);
            assert(status == STATUS_NEW,'prom already processed');
        }


    }
    
   

    
}