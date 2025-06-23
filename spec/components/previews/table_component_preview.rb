# frozen_string_literal: true

class TableComponentPreview < ViewComponent::Preview
  def default
    headers = [ "Name", "Email", "Role", "Status" ]
    rows = [
      [ "John Doe", "john@example.com", "Admin", "Active" ],
      [ "Jane Smith", "jane@example.com", "User", "Active" ],
      [ "Bob Johnson", "bob@example.com", "User", "Inactive" ]
    ]

    render(TableComponent.new(headers: headers, rows: rows))
  end

  def empty_state
    headers = [ "Product", "Price", "Stock" ]
    rows = []

    render(TableComponent.new(headers: headers, rows: rows))
  end

  def large_dataset
    headers = [ "ID", "Company", "Revenue", "Employees", "Founded" ]
    rows = [
      [ "1", "Acme Corp", "$10M", "50", "2015" ],
      [ "2", "Tech Solutions", "$25M", "120", "2010" ],
      [ "3", "Global Industries", "$100M", "500", "2005" ],
      [ "4", "StartupXYZ", "$2M", "15", "2020" ],
      [ "5", "Enterprise Co", "$500M", "2000", "1995" ]
    ]

    render(TableComponent.new(headers: headers, rows: rows))
  end
end
