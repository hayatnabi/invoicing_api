require 'prawn'
require 'securerandom'
require 'fileutils'

class Api::V1::InvoicesController < ApplicationController
  def create
    buyer = invoice_params[:buyer] || {}
    seller = invoice_params[:seller] || {}
    items = invoice_params[:items] || []
    currency = invoice_params[:currency] || "USD"
    # Convert all item keys to symbols
    items = items.map { |item| item.to_h.symbolize_keys }
    # Calculate totals
    subtotal = items.sum { |item| item[:quantity].to_f * item[:unit_price].to_f }
    tax_rate = tax_percentage_for(seller[:country])
    tax = (subtotal * tax_rate).round(2)
    total = (subtotal + tax).round(2)
    # Generate PDF
    relative_path = generate_invoice_pdf(buyer, seller, items, subtotal, tax, total, currency)
    render json: {
      subtotal: subtotal,
      tax: tax,
      total: total,
      currency: currency,
      pdf_url: relative_path
    }
  end

  private
  def invoice_params
    params.permit(
      :currency,
      buyer: [:name, :address, :country],
      seller: [:name, :address, :country, :tax_id],
      items: [:name, :quantity, :unit_price]
    )
  end


  def tax_percentage_for(country)
    case country
      when "US" then 0.07
      when "UK" then 0.20
      when "IN" then 0.18
      when "PK" then 0.60
      else 0.0
    end
  end

  def generate_invoice_pdf(buyer, seller, items, subtotal, tax, total, currency)
    filename = "invoice_#{SecureRandom.hex(4)}.pdf"
    filepath = Rails.root.join("public", "invoices", filename)

    FileUtils.mkdir_p(File.dirname(filepath))

    Prawn::Document.generate(filepath) do |pdf|
      pdf.text "Invoice", size: 24, style: :bold
      pdf.move_down 10

      pdf.text "Seller: #{seller[:name]}\n#{seller[:address]}\nTax ID: #{seller[:tax_id]}"
      pdf.move_down 5
      pdf.text "Buyer: #{buyer[:name]}\n#{buyer[:address]}"
      pdf.move_down 20

      data = [["Item", "Qty", "Unit Price", "Total"]] +
             items.map do |item|
               [
                 item[:name],
                 item[:quantity],
                 "#{currency} #{item[:unit_price]}",
                 "#{currency} #{item[:quantity].to_f * item[:unit_price].to_f}"
               ]
             end

      pdf.table(data, header: true)
      pdf.move_down 10

      pdf.text "Subtotal: #{currency} #{subtotal}"
      pdf.text "Tax (#{(tax / subtotal * 100).round(2)}%): #{currency} #{tax}"
      pdf.text "Total: #{currency} #{total}", style: :bold
    end

    "/invoices/#{filename}"
  end
end
