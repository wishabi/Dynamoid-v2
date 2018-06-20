require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Dynamoid::Persistence do
  let(:address) { Address.new }

  context 'without AWS keys' do
    unless ENV['ACCESS_KEY'] && ENV['SECRET_KEY']
      before do
        Dynamoid.adapter.delete_table(Address.table_name) if Dynamoid.adapter.list_tables.include?(Address.table_name)
      end

      it 'creates a table' do
        Address.create_table(table_name: Address.table_name)

        expect(Dynamoid.adapter.list_tables).to include 'dynamoid_tests_addresses'
      end

      it 'checks if a table already exists' do
        Address.create_table(table_name: Address.table_name)

        expect(Address.table_exists?(Address.table_name)).to be_truthy
        expect(Address.table_exists?('crazytable')).to be_falsey
      end
    end
  end

  describe 'delete_table' do
    it 'deletes the table' do
      Address.create_table
      Address.delete_table

      tables = Dynamoid.adapter.list_tables
      expect(tables.include?(Address.table_name)).to be_falsey
    end
  end

  describe 'record deletion' do
    let(:klass) do
      Class.new do
        include Dynamoid::Document
        table name: :addresses
        field :city

        before_destroy {|i|
          # Halting the callback chain in active record changed with Rails >= 5.0.0.beta1
          # We now have to throw :abort to halt the callback chain
          # See: https://github.com/rails/rails/commit/bb78af73ab7e86fd9662e8810e346b082a1ae193
          if ActiveModel::VERSION::MAJOR < 5
            false
          else
            throw :abort
          end
        }
      end
    end

    describe 'destroy' do
      it 'deletes an item completely' do
        @user = User.create(name: 'Josh')
        @user.destroy

        expect(Dynamoid.adapter.read('dynamoid_tests_users', @user.id)).to be_nil
      end

      it 'returns false when destroy fails (due to callback)' do
        a = klass.create!
        expect(a.destroy).to eql false
        expect(klass.first.id).to eql a.id
      end
    end

    describe 'destroy!' do
      it 'deletes the item' do
        address.save!
        address.destroy!
        expect(Address.count).to eql 0
      end

      it 'raises exception when destroy fails (due to callback)' do
        a = klass.create!
        expect { a.destroy! }.to raise_error(Dynamoid::Errors::RecordNotDestroyed)
      end
    end
  end

  describe 'dump_object' do
    it 'converts empty strings to null in the hash values' do
      hash = {:first_name => "joe", :last_name => '', :age => 23}
      expect(Address.new.send(:dump_object, hash)).to eql({
        :first_name=>"joe",
        :last_name=>nil,
        :age=>23
      })
    end

    it 'converts empty strings to null for the array values' do
      arr = [1, 2, 3, nil, '']
      expect(Address.new.send(:dump_object, arr)).to eql([1, 2, 3, nil, nil])
    end

    it 'converts empty strings to null for the set values' do
      set = Set.new([1, 2, 3, nil, ''])
      expect(Address.new.send(:dump_object, set)).to eql(Set.new([1, 2, 3, nil]))
    end

    it 'converts empty strings to null for hash, array and set' do
      obj = {
        :hash => {
          :first_name => "joe",
          :last_name => "",
          :info => {
            :set => Set.new([1, 2, 3, '']),
            :arr => [4, 5, '', 6]
          }
        }
      }
      expect(Address.new.send(:dump_object, obj)).to eql({
        :hash => {
          :first_name => "joe",
          :last_name => nil,
          :info => {
            :set => Set.new([1, 2, 3, nil]),
            :arr => [4, 5, nil, 6]
          }
        }
      })
    end
  end

  it 'assigns itself an id on save' do
    address.save

    expect(Dynamoid.adapter.read('dynamoid_tests_addresses', address.id)[:id]).to eq address.id
  end

  it 'prevents concurrent writes to tables with a lock_version' do
    address.save!
    a1 = address
    a2 = Address.find(address.id)

    a1.city = 'Seattle'
    a2.city = 'San Francisco'

    a1.save!
    expect { a2.save! }.to raise_exception(Dynamoid::Errors::StaleObjectError)
  end

  it 'assigns itself an id on save only if it does not have one' do
    address.id = 'test123'
    address.save

    expect(Dynamoid.adapter.read('dynamoid_tests_addresses', 'test123')).to_not be_empty
  end

  it 'has a table name' do
    expect(Address.table_name).to eq 'dynamoid_tests_addresses'
  end

  context 'with namespace is empty' do
    def reload_address
      Object.send(:remove_const, 'Address')
      load 'app/models/address.rb'
    end

    namespace = Dynamoid::Config.namespace

    before do
      reload_address
      Dynamoid.configure do |config|
        config.namespace = ''
      end
    end

    after do
      reload_address
      Dynamoid.configure do |config|
        config.namespace = namespace
      end
    end

    it 'does not add a namespace prefix to table names' do
      table_name = Address.table_name
      expect(Dynamoid::Config.namespace).to be_empty
      expect(table_name).to eq 'addresses'
    end
  end

  context 'with timestamps set to false' do
    def reload_address
      Object.send(:remove_const, 'Address')
      load 'app/models/address.rb'
    end

    timestamps = Dynamoid::Config.timestamps

    before do
      reload_address
      Dynamoid.configure do |config|
        config.timestamps = false
      end
    end

    after do
      reload_address
      Dynamoid.configure do |config|
        config.timestamps = timestamps
      end
    end

    it 'sets nil to created_at and updated_at' do
      address = Address.create
      expect(address.created_at).to be_nil
      expect(address.updated_at).to be_nil
    end
  end

  it 'deletes an item completely' do
    @user = User.create(name: 'Josh')
    @user.destroy

    expect(Dynamoid.adapter.read('dynamoid_tests_users', @user.id)).to be_nil
  end

  it 'keeps string attributes as strings' do
    @user = User.new(name: 'Josh')
    expect(@user.send(:dump)[:name]).to eq 'Josh'
  end

  it 'keeps raw Hash attributes as a Hash' do
    config = {acres: 5, trees: {cyprus: 30, poplar: 10, joshua: 1}, horses: ['Lucky', 'Dummy'], lake: 1, tennis_court: 1}
    @addr = Address.new(config: config)
    expect(@addr.send(:dump)[:config]).to eq config
  end

  it 'keeps raw Array attributes as an Array' do
    config = ['windows', 'roof', 'doors']
    @addr = Address.new(config: config)
    expect(@addr.send(:dump)[:config]).to eq config
  end

  it 'keeps raw String attributes as a String' do
    config = 'Configy'
    @addr = Address.new(config: config)
    expect(@addr.send(:dump)[:config]).to eq config
  end

  it 'keeps raw Number attributes as a Number' do
    config = 100
    @addr = Address.new(config: config)
    expect(@addr.send(:dump)[:config]).to eq config
  end

  context 'transforms booleans' do
    it 'handles true' do
      deliverable = true
      @addr = Address.new(deliverable: deliverable)
      expect(@addr.send(:dump)[:deliverable]).to eq 't'
    end

    it 'handles false' do
      deliverable = false
      @addr = Address.new(deliverable: deliverable)
      expect(@addr.send(:dump)[:deliverable]).to eq 'f'
    end

    it 'handles t' do
      deliverable = 't'
      @addr = Address.new(deliverable: deliverable)
      expect(@addr.send(:dump)[:deliverable]).to eq 't'
    end

    it 'handles f' do
      deliverable = 'f'
      @addr = Address.new(deliverable: deliverable)
      expect(@addr.send(:dump)[:deliverable]).to eq 'f'
    end
  end

  context 'when dumps datetime attribute' do
    it 'loads time in local time zone if config.application_timezone == :local', application_timezone: :local do
      time = Time.now
      user = User.create(last_logged_in_at: time)
      user = User.find(user.id)
      expect(user.last_logged_in_at).to be_a(DateTime)
      # we can't compare objects directly because lose precision of milliseconds in conversions
      expect(user.last_logged_in_at.to_s).to eq time.to_datetime.to_s
    end

    it 'loads time in specified time zone if config.application_timezone == time zone name', application_timezone: 'Hawaii' do
      time = '2017-06-20 08:00:00 +0300'.to_time
      user = User.create(last_logged_in_at: time)
      user = User.find(user.id)
      expect(user.last_logged_in_at).to eq '2017-06-19 19:00:00 -1000'.to_datetime # Hawaii UTC-10
    end

    it 'loads time in UTC if config.application_timezone = :utc', application_timezone: :utc do
      time = '2017-06-20 08:00:00 +0300'.to_time
      user = User.create(last_logged_in_at: time)
      user = User.find(user.id)
      expect(user.last_logged_in_at).to eq '2017-06-20 05:00:00 +0000'.to_datetime
    end

    it 'can be used as sort key' do
      klass = new_class do
        range :expired_at, :datetime
      end

      models = (1..100).map { klass.create(expired_at: Time.now) }
      loaded_models = models.map do |m|
        klass.find(m.id, range_key: klass.dump_field(m.expired_at, klass.attributes[:expired_at]))
      end

      expect do
        loaded_models.map do |m|
          klass.find(m.id, range_key: klass.dump_field(m.expired_at, klass.attributes[:expired_at]))
        end
      end.not_to raise_error
    end
  end

  it 'dumps date attributes' do
    address = Address.create(registered_on: '2017-06-18'.to_date)
    expect(Address.find(address.id).registered_on).to eq '2017-06-18'.to_date

    # check internal format - days since 1970-01-01
    expect(Address.find(address.id).send(:dump)[:registered_on])
      .to eq ('2017-06-18'.to_date - Date.new(1970, 1, 1)).to_i
  end

  it 'dumps integer attributes' do
    @subscription = Subscription.create(length: 10)
    expect(@subscription.send(:dump)[:length]).to eq 10
  end

  it 'dumps set attributes' do
    @subscription = Subscription.create(length: 10)
    @magazine = @subscription.magazine.create

    expect(@subscription.send(:dump)[:magazine_ids]).to eq Set[@magazine.hash_key]
  end

  it 'handles nil attributes properly' do
    expect(Address.undump(nil)).to be_a(Hash)
  end

  it 'dumps and undump a serialized field' do
    address.options = (hash = {:x => [1, 2], 'foobar' => 3.14})
    expect(Address.undump(address.send(:dump))[:options]).to eq hash
  end

  it 'dumps and undumps an integer in number field' do
    expect(Address.undump(Address.new(latitude: 123).send(:dump))[:latitude]).to eq 123
  end

  it 'dumps and undumps a float in number field' do
    expect(Address.undump(Address.new(latitude: 123.45).send(:dump))[:latitude]).to eq 123.45
  end

  it 'dumps and undumps a BigDecimal in number field' do
    expect(Address.undump(Address.new(latitude: BigDecimal.new(123.45, 3)).send(:dump))[:latitude]).to eq 123
  end

  it 'dumps and undumps a Boolean in :boolean field' do
    expect(Address.undump(Address.new(deliverable: true).send(:dump))[:deliverable]).to eq true
  end

  it 'dumps and undumps a Hash in :hash field' do
    h = {:population => 1000, :city => ''}
    expect(Address.undump(Address.new(info: h).send(:dump))[:info]).to eq({
      :population => 1000,
      :city => nil
    })
  end

  it 'dumps and undumps a date' do
    date = '2017-06-18'.to_date
    expect(
      Address.undump(Address.new(registered_on: date).send(:dump))[:registered_on]
    ).to eq date
  end

  it 'supports empty containers in `serialized` fields' do
    u = User.create(name: 'Philip')
    u.favorite_colors = Set.new
    u.save!

    u = User.find(u.id)
    expect(u.favorite_colors).to eq Set.new
  end

  it 'supports array being empty' do
    user = User.create(todo_list: [])
    expect(User.find(user.id).todo_list).to eq []
  end

  it 'saves empty set as nil' do
    tweet = Tweet.create(group: 'one', tags: [])
    expect(Tweet.find_by_tweet_id(tweet.tweet_id).tags).to eq nil
  end

  it 'saves empty string as nil' do
    user = User.create(name: '')
    expect(User.find(user.id).name).to eq nil
  end

  it 'saves attributes with nil value' do
    user = User.create(name: nil)
    expect(User.find(user.id).name).to eq nil
  end

  it 'supports container types being nil' do
    u = User.create(name: 'Philip')
    u.todo_list = nil
    u.save!

    u = User.find(u.id)
    expect(u.todo_list).to be_nil
  end

  [true, false].each do |bool|
    it "dumps a #{bool} boolean field" do
      address.deliverable = bool
      expect(Address.undump(address.send(:dump))[:deliverable]).to eq bool
    end
  end

  describe "Boolean field" do
    context "stored in string format" do
      let(:klass) do
        new_class do
          field :active, :boolean
        end
      end

      it "saves false as 'f'" do
        obj = klass.create(active: false)
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:active]).to eq "f"
      end

      it "saves 'f' as 'f'" do
        obj = klass.create(active: "f")
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:active]).to eq "f"
      end

      it "saves true as 't'" do
        obj = klass.create(active: true)
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:active]).to eq "t"
      end

      it "saves 't' as 't'" do
        obj = klass.create(active: 't')
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:active]).to eq "t"
      end
    end

    context "stored in boolean format" do
      let(:klass) do
        new_class do
          field :active, :boolean, store_as_native_boolean: true
        end
      end

      it "saves false as false" do
        obj = klass.create(active: false)
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:active]).to eq false
      end

      it "saves true as true" do
        obj = klass.create(active: true)
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:active]).to eq true
      end

      it "saves and loads boolean field correctly" do
        obj = klass.create(active: true)
        expect(klass.find(obj.hash_key).active).to eq true

        obj = klass.create(active: false)
        expect(klass.find(obj.hash_key).active).to eq false
      end
    end
  end

  describe "Datetime field" do
    context "Stored in :number format" do
      let(:klass) do
        new_class do
          field :sent_at, :datetime
        end
      end

      it "saves time as :number" do
        time = Time.now
        obj = klass.create(sent_at: time)
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:sent_at]).to eq BigDecimal("%d.%09d" % [time.to_i, time.nsec])
      end

      it "saves date as :number" do
        date = Date.today
        obj = klass.create(sent_at: date)
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:sent_at]).to eq BigDecimal("%d.%09d" % [date.to_time.to_i, date.to_time.nsec])
      end
    end

    context "Stored in :string format" do
      let(:klass) do
        new_class do
          field :sent_at, :datetime, { store_as_string: true }
        end
      end

      it "saves time as a :string" do
        time = Time.now
        obj = klass.create(sent_at: time)
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:sent_at]).to eq time.iso8601
      end

      it "saves date as :string" do
        date = Date.today
        obj = klass.create(sent_at: date)
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:sent_at]).to eq date.to_time.iso8601
      end

      it 'saves as :string if global option :store_date_time_as_string is true' do
        klass2 = new_class do
          field :sent_at, :datetime
        end

        store_datetime_as_string = Dynamoid.config.store_datetime_as_string
        Dynamoid.config.store_datetime_as_string = true

        time = Time.now
        obj = klass2.create(sent_at: time)
        attributes = Dynamoid.adapter.get_item(klass2.table_name, obj.hash_key)
        expect(attributes[:sent_at]).to eq time.iso8601

        Dynamoid.config.store_datetime_as_string = store_datetime_as_string
      end

      it 'prioritize field option over global one' do
        store_datetime_as_string = Dynamoid.config.store_datetime_as_string
        Dynamoid.config.store_datetime_as_string = false

        time = Time.now
        obj = klass.create(sent_at: time)
        attributes = Dynamoid.adapter.get_item(klass.table_name, obj.hash_key)
        expect(attributes[:sent_at]).to eq time.iso8601

        Dynamoid.config.store_datetime_as_string = store_datetime_as_string
      end
    end
  end

  describe 'Date field' do
    context 'stored in :string format' do
      it 'stores in ISO 8601 format' do
        klass = new_class do
          field :signed_up_on, :date, store_as_string: true
        end

        model = klass.create(signed_up_on: '25-09-2017'.to_date)
        expect(klass.find(model.id).signed_up_on).to eq('25-09-2017'.to_date)

        attributes = Dynamoid.adapter.get_item(klass.table_name, model.id)
        expect(attributes[:signed_up_on]).to eq '2017-09-25'
      end

      it 'stores in string format when global option :store_date_as_string is true' do
        klass = new_class do
          field :signed_up_on, :date
        end

        store_date_as_string = Dynamoid.config.store_date_as_string
        Dynamoid.config.store_date_as_string = true

        model = klass.create(signed_up_on: '25-09-2017'.to_date)
        attributes = Dynamoid.adapter.get_item(klass.table_name, model.id)
        expect(attributes[:signed_up_on]).to eq '2017-09-25'

        Dynamoid.config.store_date_as_string = store_date_as_string
      end

      it 'prioritize field option over global one' do
        klass = new_class do
          field :signed_up_on, :date, store_as_string: true
        end

        store_date_as_string = Dynamoid.config.store_date_as_string
        Dynamoid.config.store_date_as_string = false

        model = klass.create(signed_up_on: '25-09-2017'.to_date)
        attributes = Dynamoid.adapter.get_item(klass.table_name, model.id)
        expect(attributes[:signed_up_on]).to eq '2017-09-25'

        Dynamoid.config.store_date_as_string = store_date_as_string
      end
    end
  end

  describe "Set field" do
    let(:klass) do
      new_class do
        field :string_set, :set
        field :integer_set, :set, { of: :integer }
        field :number_set, :set, { of: :number }
      end
    end

    it "stored a string set" do
      obj = klass.create(string_set: Set.new(['a','b']))
      expect(obj.reload[:string_set]).to eq(Set.new(['a','b']))
    end

    it "stored an integer set" do
      obj = klass.create(integer_set: Set.new([1,2]))
      expect(obj.reload[:integer_set]).to eq(Set.new([1,2]))
    end

    it "stored a number set" do
      obj = klass.create(number_set: Set.new([1,2]))
      expect(obj.reload[:number_set]).to eq(Set.new([BigDecimal(1),BigDecimal(2)]))
    end
  end

  it 'raises on an invalid boolean value' do
    expect do
      address.deliverable = true
      data = address.send(:dump)
      data[:deliverable] = 'foo'
      Address.undump(data)
    end.to raise_error(ArgumentError)
  end

  it 'loads a hash into a serialized field' do
    hash = {foo: :bar}
    expect(Address.new(options: hash).options).to eq hash
  end

  it 'loads attributes from a hash' do
    @time = DateTime.now
    @hash = {name: 'Josh', created_at: BigDecimal("%d.%09d" % [@time.to_i, @time.nsec])}

    expect(User.undump(@hash)[:name]).to eq 'Josh'
    expect(User.undump(@hash)[:created_at]).to eq @time
  end

  it 'runs the before_create callback only once' do
    expect_any_instance_of(CamelCase).to receive(:doing_before_create).once.and_return(true)

    CamelCase.create
  end

  it 'runs after save callbacks when doing #create' do
    expect_any_instance_of(CamelCase).to receive(:doing_after_create).once.and_return(true)

    CamelCase.create
  end

  it 'runs after save callbacks when doing #save' do
    expect_any_instance_of(CamelCase).to receive(:doing_after_create).once.and_return(true)

    CamelCase.new.save
  end

  it 'works with a HashWithIndifferentAccess' do
    hash = ActiveSupport::HashWithIndifferentAccess.new('city' => 'Atlanta')

    expect{Address.create(hash)}.to_not raise_error
  end

  context 'create' do
    {
      Tweet   => ['with range',    { tweet_id: 1, group: 'abc' }],
      Message => ['without range', { message_id: 1, text: 'foo', time: DateTime.now }]
    }.each_pair do |clazz, fields|
      it "checks for existence of an existing object #{fields[0]}" do
        t1 = clazz.new(fields[1])
        t2 = clazz.new(fields[1])

        t1.save
        expect do
          t2.save!
        end.to raise_exception Dynamoid::Errors::RecordNotUnique
      end
    end
  end

  context 'unknown fields' do
    let(:clazz) do
      Class.new do
        include Dynamoid::Document
        table name: :addresses

        field :city
        field :options, :serialized
        field :deliverable, :bad_type_specifier
      end
    end

    it 'raises when undumping a column with an unknown field type' do
      expect do
        clazz.new(deliverable: true) # undump is called here
      end.to raise_error(ArgumentError)
    end

    it 'raises when dumping a column with an unknown field type' do
      doc = clazz.new
      doc.deliverable = true
      expect do
        doc.dump
      end.to raise_error(ArgumentError)
    end
  end

  describe 'save' do
    it 'creates table if it does not exist' do
      klass = Class.new do
        include Dynamoid::Document
        table name: :foo_bars
      end

      expect { klass.create }.not_to raise_error(Aws::DynamoDB::Errors::ResourceNotFoundException)
      expect(klass.create.id).to be_present
    end
  end

  context 'update' do

    before :each do
      @tweet = Tweet.create(tweet_id: 1, group: 'abc', count: 5, tags: Set.new(['db', 'sql']), user_name: 'john')
    end

    it 'runs before_update callbacks when doing #update' do
      expect_any_instance_of(CamelCase).to receive(:doing_before_update).once.and_return(true)

      CamelCase.create(color: 'blue').update do |t|
        t.set(color: 'red')
      end
    end

    it 'runs after_update callbacks when doing #update' do
      expect_any_instance_of(CamelCase).to receive(:doing_after_update).once.and_return(true)

      CamelCase.create(color: 'blue').update do |t|
        t.set(color: 'red')
      end
    end

    it 'support add/delete operation on a field' do
      @tweet.update do |t|
        t.add(count: 3)
        t.delete(tags: Set.new(['db']))
      end

      expect(@tweet.count).to eq(8)
      expect(@tweet.tags.to_a).to eq(['sql'])
    end

    it 'checks the conditions on update' do
      result = @tweet.update(if: { count: 5 }) do |t|
        t.add(count: 3)
      end
      expect(result).to be_truthy

      expect(@tweet.count).to eq(8)

      result = @tweet.update(if: { count: 5 }) do |t|
        t.add(count: 3)
      end
      expect(result).to be_falsey

      expect(@tweet.count).to eq(8)

      expect do
        @tweet.update!(if: { count: 5 }) do |t|
          t.add(count: 3)
        end
      end.to raise_error(Dynamoid::Errors::StaleObjectError)
    end

    it 'prevents concurrent saves to tables with a lock_version' do
      address.save!
      a2 = Address.find(address.id)
      a2.update! { |a| a.set(city: 'Chicago') }

      expect do
        address.city = 'Seattle'
        address.save!
      end.to raise_error(Dynamoid::Errors::StaleObjectError)
    end

  end

  context 'delete' do
    it 'deletes model with datetime range key' do
      expect do
        msg = Message.create!(message_id: 1, time: DateTime.now, text: 'Hell yeah')
        msg.destroy
      end.to_not raise_error
    end

    context 'with lock version' do
      it 'deletes a record if lock version matches' do
        address.save!
        expect { address.destroy }.to_not raise_error
      end

      it 'does not delete a record if lock version does not match' do
        address.save!
        a1 = address
        a2 = Address.find(address.id)

        a1.city = 'Seattle'
        a1.save!

        expect { a2.destroy }.to raise_exception(Dynamoid::Errors::StaleObjectError)
      end

      it 'skips the lock check if :skip_lock_check = true' do
        address.save!
        a1 = address
        a2 = Address.find(address.id)

        a1.city = 'Seattle'
        a1.save!

        a2.destroy(:skip_lock_check => true)
        expect { Address.find(address.id) }.to raise_exception(Dynamoid::Errors::RecordNotFound)
      end

      it 'uses the correct lock_version even if it is modified' do
        address.save!
        a1 = address
        a1.lock_version = 100

        expect { a1.destroy }.to_not raise_error
      end
    end
  end

  context 'single table inheritance' do
    let(:vehicle) { Vehicle.create }
    let(:car) { Car.create(power_locks: false) }
    let(:sub) { NuclearSubmarine.create(torpedoes: 5) }

    it 'saves subclass objects in the parent table' do
      c = car
      expect(Vehicle.find(c.id)).to eq c
    end

    it 'loads subclass item when querying the parent table' do
      c = car
      s = sub

      Vehicle.all.to_a.tap { |v|
        expect(v).to include(c)
        expect(v).to include(s)
      }
    end

    it 'does not load parent item when quering the child table' do
      vehicle && car

      expect(Car.all).to contain_exactly(car)
      expect(Car.all).not_to include(vehicle)
    end

    it 'does not load items of sibling class' do
      car && sub

      expect(Car.all).to contain_exactly(car)
      expect(Car.all).not_to include(sub)
    end
  end

  describe ':raw datatype persistence' do
    subject { Address.new() }

    it 'it persists raw Hash and reads the same back' do
      config = {acres: 5, trees: {cyprus: 30, poplar: 10, joshua: 1}, horses: ['Lucky', 'Dummy'], lake: 1, tennis_court: 1}
      subject.config = config
      subject.save!
      subject.reload
      expect(subject.config).to eq config
    end

    it 'it persists raw Array and reads the same back' do
      config = ['windows', 'doors', 'roof']
      subject.config = config
      subject.save!
      subject.reload
      expect(subject.config).to eq config
    end

    it 'it persists raw Number and reads the same back' do
      config = 100
      subject.config = config
      subject.save!
      subject.reload
      expect(subject.config).to eq config
    end

    it 'it persists raw String and reads the same back' do
      config = 'Configy'
      subject.config = config
      subject.save!
      subject.reload
      expect(subject.config).to eq config
    end

    it 'it persists raw value, then reads back, then deletes the value by setting to nil, persists and reads the nil back' do
      config = 'To become nil'
      subject.config = config
      subject.save!
      subject.reload
      expect(subject.config).to eq config

      subject.config = nil
      subject.save!
      subject.reload
      expect(subject.config).to be_nil
    end
  end

  describe 'class-type fields' do
    subject { doc_class.new }

    context 'when Money can load itself and Money instances can dump themselves with Dynamoid-specific methods' do
      let(:doc_class) do
        Class.new do
          def self.name; 'Doc'; end

          include Dynamoid::Document

          field :price, MoneyInstanceDump
        end
      end

      before(:each) do
        subject.price = MoneyInstanceDump.new(BigDecimal.new('5'))
        subject.save!
      end

      it 'round-trips using Dynamoid-specific methods' do
        expect(doc_class.all.first).to eq subject
      end

      it 'is findable as a string' do
        pending 'casting to declared type is not supported yet'
        expect(doc_class.where(price: '5.0').first).to eq subject
      end
    end

    context 'when MoneyAdapter dumps/loads a class that does not directly support Dynamoid\'s interface' do
      let(:doc_class) do
        Class.new do
          def self.name; 'Doc'; end

          include Dynamoid::Document

          field :price, MoneyAdapter
        end
      end

      before(:each) do
        subject.price = Money.new(BigDecimal.new('5'))
        subject.save!
        subject.reload
      end

      it 'round-trips using Dynamoid-specific methods' do
        expect(doc_class.all.first.price).to eq subject.price
      end

      it 'is findable as a string' do
        pending 'casting to declared type is not supported yet'
        expect(doc_class.where(price: '5.0').first).to eq subject
      end

      it 'is a Money object' do
        expect(subject.price).to be_a Money
      end
    end

    context 'when Money has Dynamoid-specific serialization methods and is a range' do
      let(:doc_class) do
        Class.new do
          def self.name; 'Doc'; end

          include Dynamoid::Document

          range :price, MoneyAsNumber
        end
      end

      before(:each) do
        subject.price = MoneyAsNumber.new(BigDecimal.new('5'))
        subject.save!
      end

      it 'round-trips using Dynamoid-specific methods' do
        expect(doc_class.all.first.price).to eq subject.price
      end

      it 'is findable with number semantics' do
        pending 'casting to declared type is not supported yet'
        # With the primary key, we're forcing a Query rather than a Scan because of https://github.com/Dynamoid/Dynamoid/issues/6
        primary_key = subject.id
        expect(doc_class.where(id: primary_key).where('price.gt' => 4).first).to_not be_nil
      end
    end
  end

  describe '.import' do
    before do
      Address.create_table
      User.create_table
      Tweet.create_table
    end

    it 'creates multiple documents' do
      expect {
        Address.import([{city: 'Chicago'}, {city: 'New York'}])
      }.to change { Address.count }.by(2)
    end

    it 'returns created documents' do
      addresses = Address.import([{city: 'Chicago'}, {city: 'New York'}])
      expect(addresses[0].city).to eq('Chicago')
      expect(addresses[1].city).to eq('New York')
    end

    it 'does not validate documents' do
      klass = Class.new do
        include Dynamoid::Document
        field :city
        validates :city, presence: true

        def self.name; 'Address'; end
      end

      addresses = klass.import([{city: nil}, {city: 'Chicago'}])
      expect(addresses[0].persisted?).to be true
      expect(addresses[1].persisted?).to be true
    end

    it 'does not run callbacks' do
      klass = Class.new do
        include Dynamoid::Document
        field :city
        validates :city, presence: true

        def self.name; 'Address'; end

        before_save { raise 'before save callback called' }
      end

      expect { klass.import([{city: 'Chicago'}]) }.not_to raise_error
    end

    it 'makes batch operation' do
      expect(Dynamoid.adapter).to receive(:batch_write_item).and_call_original
      Address.import([{city: 'Chicago'}, {city: 'New York'}])
    end

    it 'supports empty containers in `serialized` fields' do
      users = User.import([name: 'Philip', favorite_colors: Set.new])

      user = User.find(users[0].id)
      expect(user.favorite_colors).to eq Set.new
    end

    it 'supports array being empty' do
      users = User.import([{todo_list: []}])

      user = User.find(users[0].id)
      expect(user.todo_list).to eq []
    end

    it 'saves empty set as nil' do
      tweets = Tweet.import([{group: 'one', tags: []}])

      tweet = Tweet.find_by_tweet_id(tweets[0].tweet_id)
      expect(tweet.tags).to eq nil
    end

    it 'saves empty string as nil' do
      users = User.import([{name: ''}])

      user = User.find(users[0].id)
      expect(user.name).to eq nil
    end

    it 'saves attributes with nil value' do
      users = User.import([{name: nil}])

      user = User.find(users[0].id)
      expect(user.name).to eq nil
    end

    it 'supports container types being nil' do
      users = User.import([{name: 'Philip', todo_list: nil}])

      user = User.find(users[0].id)
      expect(user.todo_list).to eq nil
    end

    context 'backoff is specified' do
      let(:backoff_strategy) do
        ->(_) { -> { @counter += 1 } }
      end

      before do
        @old_backoff = Dynamoid.config.backoff
        @old_backoff_strategies = Dynamoid.config.backoff_strategies.dup

        @counter = 0
        Dynamoid.config.backoff_strategies[:simple] = backoff_strategy
        Dynamoid.config.backoff = { simple: nil }
      end

      after do
        Dynamoid.config.backoff = @old_backoff
        Dynamoid.config.backoff_strategies = @old_backoff_strategies
      end

      it 'creates multiple documents' do
        expect {
          Address.import([{city: 'Chicago'}, {city: 'New York'}])
        }.to change { Address.count }.by(2)
      end

      it 'uses specified backoff when some items are not processed' do
        # dynamodb-local ignores provisioned throughput settings
        # so we cannot emulate unprocessed items - let's stub

        klass = new_class
        table_name = klass.table_name
        items = (1 .. 3).map(&:to_s).map { |id| { id: id } }

        responses = [
          double('response 1', unprocessed_items: { table_name => [
            double(put_request: double(item: { id: '3' }))
          ]}),
          double('response 2', unprocessed_items: { table_name => [
            double(put_request: double(item: { id: '3' }))
          ]}),
          double('response 3', unprocessed_items: nil)
        ]
        allow(Dynamoid.adapter.client).to receive(:batch_write_item).and_return(*responses)

        klass.import(items)
        expect(@counter).to eq 2
      end

      it 'uses new backoff after successful call without unprocessed items' do
        # dynamodb-local ignores provisioned throughput settings
        # so we cannot emulate unprocessed items - let's stub

        klass = new_class
        table_name = klass.table_name
        # batch_write_item processes up to 15 items at once
        # so we emulate 4 calls with items
        items = (1 .. 50).map(&:to_s).map { |id| { id: id } }

        responses = [
          double('response 1', unprocessed_items: { table_name => [
            double(put_request: double(item: { id: '25' }))
          ]}),
          double('response 3', unprocessed_items: nil),
          double('response 2', unprocessed_items: { table_name => [
            double(put_request: double(item: { id: '25' }))
          ]}),
          double('response 3', unprocessed_items: nil)
        ]
        allow(Dynamoid.adapter.client).to receive(:batch_write_item).and_return(*responses)

        expect(backoff_strategy).to receive(:call).exactly(2).times.and_call_original
        klass.import(items)
        expect(@counter).to eq 2
      end
    end
  end
end
