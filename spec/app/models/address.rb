class Address
  include Dynamoid::Document

  field :city
  field :options, :serialized
  field :deliverable, :boolean
  field :latitude, :number
  field :info, :hash
  field :config, :raw
  field :registered_on, :date

  field :lock_version, :integer # Provides Optimistic Locking

  def zip_code=(zip_code)
    self.city = 'Chicago'
  end
end
