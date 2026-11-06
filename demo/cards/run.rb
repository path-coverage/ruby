# Runs cells.rb under path coverage, calling each method so its
# card shows every kind of cell, and writes the JSON reports to
# COVERAGE_DIR, for html-reporter to draw. Run by
# bin/capture_card_images.sh.
require 'path_coverage'

PathCoverage.start do
  root __dir__
  cover 'cells.rb'
  cover 'long.rb'
  cover 'remember.rb'
  cover 'label.rb'
  cover 'owner_of.rb'
  cover 'any_odd.rb'
  cover 'odds.rb'
  cover 'notify.rb'
  coverage_dir ENV.fetch('COVERAGE_DIR')
  report
  treat 'any?', as: :nonempty
end

require_relative 'cells'
require_relative 'long'
require_relative 'remember'
require_relative 'label'
require_relative 'owner_of'
require_relative 'any_odd'
require_relative 'odds'
require_relative 'notify'

User = Data.define(:name)
Member = Data.define(:account)
Account = Data.define(:owner)
Person = Data.define(:role) do
  # True for an admin.
  def admin? = role == :admin
end

# Each method is called on all but one of its paths, so each
# card shows a gap.

# Both leaves true; the first false; never the second false.
['kim', 'al'].each { |name| Cells.long?(name) }
['kim', 'al'].each { |name| long?(name) }

# A dee; no dee but a dum; never neither.
[['a', 'b'], [nil, 'b']].each { |dee, dum| remember(dee, dum) }

# A nick; no nick but a name; never neither.
[['kp', 'kim'], [nil, 'kim']].each do |nick, name|
  Cells.called(nick, name)
end

# No ids, one even, one odd, an even then an odd; never two even.
[[], [2], [1], [2, 3]].each { |ids| Cells.any_odd?(ids) }
[[], [2], [1], [2, 3]].each { |ids| any_odd?(ids) }

# No ids, one odd, one even, all odd, odd and even; never all even.
[[], [1], [2], [1, 3], [1, 2]].each { |ids| Cells.odds(ids) }
[[], [1], [2], [1, 3], [1, 2]].each { |ids| odds(ids) }

# A user; never no user.
[User.new(name: 'kim')].each { |user| Cells.name_of(user) }

# A member with no account; one whose account has an owner; never
# no member.
members = [Member.new(account: nil),
           Member.new(account: Account.new(owner: 'kim'))]
members.each { |member| owner_of(member) }

# Paid; never not.
[true].each { |paid| Cells.label(paid) }
[true].each { |paid| label(paid) }

# The overview: no user, a user not an admin, then an admin with
# no ids, one odd, one even, all odd, and odd and even; never an
# admin with all even ids.
admin = Person.new(role: :admin)
[[nil, [1]], [Person.new(role: :dev), [1]], [admin, []], [admin, [1]],
 [admin, [2]], [admin, [1, 3]], [admin, [1, 2]]].each do |user, ids|
  notify(user, ids)
end
